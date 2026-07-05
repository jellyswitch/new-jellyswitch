require "test_helper"

module Jellyswitch
  class ReportTest < ActiveSupport::TestCase
    setup do
      @operator = operators(:cowork_tahoe)
      @location = locations(:cowork_tahoe_location)
      @report   = Jellyswitch::Report.new(@operator, @location)
    end

    # An out-of-band member whose only membership basis was a group office
    # lease that has since ended is a *former* member, not a lapsed one, and
    # must not surface on the inactive-members re-engagement list.
    test "excludes out-of-band group members whose office lease has ended" do
      org = Organization.create!(
        name: "Expired Lease Co",
        operator: @operator,
        location: @location,
        out_of_band: false,
      )
      ended_subscription = Subscription.create!(
        plan: plans(:cowork_tahoe_office_lease_plan),
        subscribable: org,
        billable: org,
        active: false,
        start_date: 1.year.ago,
      )
      OfficeLease.create!(
        operator: @operator,
        location: @location,
        organization: org,
        office: offices(:office_23b),
        subscription: ended_subscription,
        start_date: 1.year.ago,
        end_date: 1.month.ago,
      )

      member = create_member(organization: org, out_of_band: true)

      assert_not_includes @report.inactive_members, member
    end

    # Control: an out-of-band member under an org whose lease is still active is
    # a genuine member; if they haven't visited recently they belong on the list.
    test "still flags out-of-band group members whose lease is active" do
      member = create_member(
        organization: organizations(:sierra_nevada_organization),
        out_of_band: true,
      )

      assert_includes @report.inactive_members, member
    end

    # Control: an out-of-band member with no organization at all is unaffected
    # by the group/lease filtering.
    test "still flags out-of-band members with no organization" do
      member = create_member(organization: nil, out_of_band: true)

      assert_includes @report.inactive_members, member
    end

    # ── Dashboard metric accuracy (Reports & Data page) ──

    # datetime_in is stored UTC; the old EXTRACT(HOUR) business-hours filter
    # ran in UTC, which shifted the 8am-6pm window to ~1-11am Pacific and
    # silently dropped every afternoon booking from utilization.
    test "room_utilization counts afternoon bookings in the location's local time" do
      utilization_room # create before the baseline so the denominator is stable
      base = @report.room_utilization
      weekday = most_recent_past_weekday

      book_room(datetime_in: weekday.in_time_zone.change(hour: 14), minutes: 300)

      assert_operator @report.room_utilization, :>, base
    end

    test "room_utilization ignores bookings outside local business hours" do
      utilization_room
      base = @report.room_utilization
      weekday = most_recent_past_weekday

      book_room(datetime_in: weekday.in_time_zone.change(hour: 3), minutes: 300)

      assert_equal base, @report.room_utilization
    end

    test "room_utilization ignores weekend bookings to match its weekday denominator" do
      utilization_room
      base = @report.room_utilization
      saturday = most_recent_past_saturday

      book_room(datetime_in: saturday.in_time_zone.change(hour: 14), minutes: 300)

      assert_equal base, @report.room_utilization
    end

    test "day_pass_count honors an explicit calendar-month range" do
      last_month = Date.current.prev_month
      create_day_pass(day: last_month.beginning_of_month + 9)
      create_day_pass(day: Date.current)

      range = last_month.beginning_of_month..last_month.end_of_month
      assert_equal 1, @report.day_pass_count(range: range)
    end

    test "day_pass_count does not count passes scheduled for future days" do
      base = @report.day_pass_count

      create_day_pass(day: Date.current + 5) # bundle day scheduled ahead

      assert_equal base, @report.day_pass_count
    end

    test "churned_members_count skips members who merely switched plans" do
      base = @report.churned_members_count

      switcher = create_member(organization: nil, out_of_band: false)
      create_subscription(user: switcher, plan: plans(:cowork_tahoe_part_time_plan), active: false)
      create_subscription(user: switcher, plan: plans(:cowork_tahoe_full_time_plan), active: true)

      genuine = create_member(organization: nil, out_of_band: false)
      create_subscription(user: genuine, plan: plans(:cowork_tahoe_part_time_plan), active: false)

      assert_equal base + 1, @report.churned_members_count
    end

    # net_member_growth previously counted new subscriptions on ANY plan
    # (including free ones) against churn on paid individual plans only, so
    # free signups inflated growth that no churn could ever offset.
    test "new_members_count counts only paid individual subscriptions" do
      base = @report.new_members_count

      free_plan = Plan.create!(
        name: "Free Community",
        interval: "monthly",
        amount_in_cents: 0,
        plan_type: "individual",
        operator: @operator,
        location: @location,
        visible: true,
        available: true,
        slug: "free-community-#{SecureRandom.hex(4)}",
        stripe_plan_id: "free-community-#{SecureRandom.hex(4)}",
      )
      freebie = create_member(organization: nil, out_of_band: false)
      create_subscription(user: freebie, plan: free_plan, active: true)

      assert_equal base, @report.new_members_count, "free plans must not count as new members"

      paid = create_member(organization: nil, out_of_band: false)
      create_subscription(user: paid, plan: plans(:cowork_tahoe_full_time_plan), active: true)

      assert_equal base + 1, @report.new_members_count
    end

    test "revenue_for_period adds the full lease check when the window covers the month" do
      repoint_lease_fixture_plan
      last_month = Date.current.prev_month
      range = last_month.beginning_of_month..last_month.end_of_month

      # office_23b_lease: sierra_nevada pays $205/mo by check — no invoices,
      # so the whole supplement belongs in a window covering the full month.
      assert_equal (paid_invoice_dollars(range) + 205.0).round,
        @report.revenue_for_period(range: range)
    end

    test "revenue_for_period pro-rates the lease check for a partial month" do
      repoint_lease_fixture_plan
      last_month = Date.current.prev_month
      range = last_month.beginning_of_month..(last_month.beginning_of_month + 14) # 15 days
      expected_lease = 205.0 * 15 / last_month.end_of_month.day

      assert_equal (paid_invoice_dollars(range) + expected_lease).round,
        @report.revenue_for_period(range: range)
    end

    # Stripe only sets due_date on emailed invoices; auto-charged card
    # invoices carry due_date = NULL. Keying revenue on due_date alone
    # dropped $18k of card revenue in a single real month.
    test "revenue counts paid card invoices that have no due_date" do
      last_month = Date.current.prev_month
      range = last_month.beginning_of_month..last_month.end_of_month
      base = @report.revenue_for_period(range: range)

      payer = create_member(organization: nil, out_of_band: false)
      create_paid_invoice(
        billable: payer,
        amount_cents: 10000,
        date: last_month.beginning_of_month.in_time_zone.change(day: 12, hour: 9),
      )

      assert_equal base + 100, @report.revenue_for_period(range: range)
    end

    # A lease org that pays via Stripe gets an invoice with NULL due_date.
    # The supplement's "does this org already have an invoice this month?"
    # check must use the same effective-date key, or the org's lease gets
    # added again on top of its real payment ($6.8k of double-counting in
    # a single real month).
    test "lease supplement is suppressed when the org paid by card that month" do
      repoint_lease_fixture_plan
      last_month = Date.current.prev_month
      range = last_month.beginning_of_month..last_month.end_of_month
      base = @report.revenue_for_period(range: range) # includes the $205 supplement

      create_paid_invoice(
        billable: organizations(:sierra_nevada_organization),
        amount_cents: 30000, # deliberately != plan amount to expose double-counting
        date: last_month.beginning_of_month.in_time_zone.change(day: 3, hour: 10),
      )

      # +$300 invoice, −$205 supplement (now covered by a real payment)
      assert_equal base + 300 - 205, @report.revenue_for_period(range: range)
    end

    # The hero tile reads as "revenue ÷ months" — it must average actual
    # complete months, not synthetic subscription snapshots, and the current
    # partial month must not drag the average down.
    test "avg_monthly_revenue equals last complete month's revenue for a 30-day period" do
      repoint_lease_fixture_plan
      last_month = Date.current.prev_month
      range = last_month.beginning_of_month..last_month.end_of_month

      payer = create_member(organization: nil, out_of_band: false)
      create_paid_invoice(
        billable: payer,
        amount_cents: 50000,
        date: last_month.beginning_of_month.in_time_zone.change(day: 10, hour: 9),
      )
      # Current-month noise that must NOT affect the average
      create_paid_invoice(billable: payer, amount_cents: 99900, date: Time.current)

      assert_equal @report.revenue_for_period(range: range), @report.avg_monthly_revenue(30)
    end

    test "avg_monthly_revenue averages the last 12 complete months for a 1-year period" do
      by_month = @report.revenue_by_month(13)
      complete = by_month.reject { |m, _| m == Date.current.beginning_of_month }
      assert_equal 12, complete.size
      assert_equal (complete.values.sum / complete.size).round, @report.avg_monthly_revenue(365)
    end

    # mrr_by_month used to filter on active-today, so every since-cancelled
    # subscription vanished from history (survivorship bias).
    test "mrr_by_month keeps a cancelled subscription in months it was active" do
      label = 3.months.ago.beginning_of_month.strftime("%b %Y")

      user = create_member(organization: nil, out_of_band: false)
      sub = create_subscription(user: user, plan: plans(:cowork_tahoe_full_time_plan), active: true)
      sub.update_column(:created_at, 6.months.ago)
      before = Jellyswitch::Report.new(@operator, @location).mrr_by_month(6)[label]

      # Cancelled today → was still active 3 months ago → must still count there
      sub.update!(active: false)
      assert_equal before, Jellyswitch::Report.new(@operator, @location).mrr_by_month(6)[label]

      # Cancelled BEFORE that month → must not count there ($205 full-time plan)
      sub.update_columns(active: false, updated_at: 5.months.ago)
      assert_equal before - 205, Jellyswitch::Report.new(@operator, @location).mrr_by_month(6)[label]
    end

    # ── History-driven day-pass forecast ──
    # forecast = recent baseline × the target month's historical index,
    # where the index is measured from THIS location's data and shrunk
    # toward 1.0 — seasonal locations get their peaks, non-seasonal
    # locations (no tourist traffic) converge on their plain average.
    # Fixture day-pass type is $200/pass. The target's sample month
    # (next month, last year) sits 11 months back — inside the baseline.

    test "forecast amplifies a month that historically outperforms its year" do
      target = Date.current.next_month.beginning_of_month
      sample = target << 12
      (1..20).each do |i|
        month = Date.current.beginning_of_month << i
        create_day_pass(day: month + 3)
      end
      3.times { |i| create_day_pass(day: sample + 5 + i) } # sample month: $800

      # baseline (last 12 complete) = (11×200 + 800)/12 = 250
      # index: 800 / (window avg 260) = 3.077 → shrunk (3.077+1)/2 = 2.038
      # forecast = 250 × 2.038 = 510
      assert_equal 510, @report.day_pass_forecast
    end

    test "forecast converges on the recent average when history shows no seasonality" do
      (1..20).each do |i|
        month = Date.current.beginning_of_month << i
        create_day_pass(day: month + 3)
      end

      # uniform history → index 1.0 → forecast = baseline = $200
      assert_equal 200, @report.day_pass_forecast
    end

    test "forecast clamps a runaway historical index at 4x" do
      target = Date.current.next_month.beginning_of_month
      sample = target << 12
      (1..20).each do |i|
        month = Date.current.beginning_of_month << i
        create_day_pass(day: month + 3)
      end
      25.times { |i| create_day_pass(day: sample + (i % 25) + 1) } # sample month: $5200 total

      # baseline = (11×200 + 5200)/12 = 616.67; raw index 7.43 → shrunk
      # 4.21 → clamped 4.0 → forecast = 616.67 × 4 = 2467
      assert_equal 2467, @report.day_pass_forecast
    end

    test "forecast for a young location is the average of its complete months" do
      create_day_pass(day: (Date.current.beginning_of_month << 2) + 3) # $200
      2.times { |i| create_day_pass(day: (Date.current.beginning_of_month << 1) + 3 + i) } # $400

      # No usable year-ago sample → index 1.0 → (200 + 400)/2 = 300
      assert_equal 300, @report.day_pass_forecast
    end

    test "day_pass_revenue_for_month ignores complimentary and future-scheduled passes" do
      last_month = Date.current.prev_month
      create_day_pass(day: last_month.beginning_of_month + 5)
      comp = create_day_pass(day: last_month.beginning_of_month + 6)
      comp.update_column(:complimentary, true)

      assert_equal 200, @report.day_pass_revenue_for_month(last_month)
      # A month in the future can hold scheduled bundle days — never revenue
      assert_equal 0.0, @report.day_pass_revenue_for_month(Date.current.next_month)
    end

    test "projected_next_month_revenue is contracted recurring plus history-driven estimates" do
      repoint_lease_fixture_plan
      expected = @report.mrr(product_filter: "memberships") +
        @report.mrr(product_filter: "offices") +
        @report.day_pass_forecast +
        @report.room_forecast

      assert_equal expected.round, @report.projected_next_month_revenue
    end

    # ── Revenue by product ──
    # Exclusive partition: linkage first (day-pass invoice ids, room
    # payment intents), then billable type; remainder = memberships.

    test "revenue_by_product puts each invoice in exactly one bucket" do
      last_month = Date.current.prev_month
      range = last_month.beginning_of_month..last_month.end_of_month
      mid = last_month.beginning_of_month.in_time_zone.change(day: 10, hour: 9)
      member = create_member(organization: nil, out_of_band: false)

      create_paid_invoice(billable: member, amount_cents: 20000, date: mid) # membership

      dp_invoice = create_paid_invoice(billable: member, amount_cents: 3500, date: mid + 1.hour)
      pass = create_day_pass(day: last_month.beginning_of_month + 9)
      pass.update_column(:invoice_id, dp_invoice.id)

      room_invoice = create_paid_invoice(billable: member, amount_cents: 4500, date: mid + 2.hours)
      room_invoice.update_column(:stripe_payment_intent_id, "pi_room_bucket_test")
      Reservation.create!(
        user: member,
        room: rooms(:small_meeting_room),
        datetime_in: 10.days.ago.in_time_zone.change(hour: 3),
        minutes: 60,
        cancelled: false,
        stripe_payment_intent_id: "pi_room_bucket_test",
      )

      create_paid_invoice(
        billable: organizations(:sierra_nevada_organization),
        amount_cents: 20500,
        date: mid + 3.hours,
      )

      result = @report.revenue_by_product(range: range)

      assert_equal 35.0, result["Day Passes"]
      assert_equal 45.0, result["Meeting Rooms"]
      assert_equal 205.0, result["Office Leases"]
      assert_equal 200.0, result["Memberships"], "day-pass/room/org invoices must not leak into Memberships"
    end

    test "user-billed lease invoices bucket under Office Leases" do
      last_month = Date.current.prev_month
      range = last_month.beginning_of_month..last_month.end_of_month
      payer = create_member(organization: nil, out_of_band: false)
      organizations(:sierra_nevada_organization).update_columns(billing_contact_id: payer.id)

      create_paid_invoice(
        billable: payer,
        amount_cents: 90000,
        date: last_month.beginning_of_month.in_time_zone.change(day: 5, hour: 10),
      )

      result = @report.revenue_by_product(range: range)
      assert_equal 900.0, result["Office Leases"]
      assert_nil result["Memberships"]
    end

    test "revenue_by_product buckets sum to the PERIOD REVENUE definition" do
      repoint_lease_fixture_plan
      last_month = Date.current.prev_month
      range = last_month.beginning_of_month..last_month.end_of_month
      member = create_member(organization: nil, out_of_band: false)
      create_paid_invoice(
        billable: member,
        amount_cents: 12300,
        date: last_month.beginning_of_month.in_time_zone.change(day: 8, hour: 11),
      )

      total = @report.revenue_by_product(range: range).values.sum
      assert_equal @report.revenue_for_period(range: range), total.round
    end

    test "current_month_forecast is MTD actuals plus the expected remainder" do
      repoint_lease_fixture_plan
      today = Date.current
      month_start = today.beginning_of_month
      frac_remaining = (today.end_of_month.day - today.day).to_f / today.end_of_month.day

      buckets = @report.revenue_by_product(range: month_start..today)
      contracted = @report.mrr(product_filter: "memberships") + @report.mrr(product_filter: "offices")
      recurring_mtd = buckets.fetch("Memberships", 0.0) + buckets.fetch("Office Leases", 0.0)
      expected = buckets.values.sum +
        @report.day_pass_forecast(month_start) * frac_remaining +
        @report.room_forecast(month_start) * frac_remaining +
        [contracted - recurring_mtd, 0].max

      assert_equal expected.round, @report.current_month_forecast
    end

    test "current_month_forecast never drops below money already received" do
      # An annual payer early in the month: MTD exceeds the contracted
      # monthly book — the recurring remainder must floor at zero, not
      # subtract.
      payer = create_member(organization: nil, out_of_band: false)
      create_paid_invoice(
        billable: payer,
        amount_cents: 5_000_000, # $50k annual payment
        date: Date.current.beginning_of_month.in_time_zone.change(hour: 9),
      )

      mtd = @report.revenue_by_product(range: Date.current.beginning_of_month..Date.current).values.sum
      assert_operator @report.current_month_forecast, :>=, mtd.round
    end

    test "lease supplement skips leases with no organization" do
      repoint_lease_fixture_plan
      last_month = Date.current.prev_month
      range = last_month.beginning_of_month..last_month.end_of_month
      base = @report.revenue_for_period(range: range)

      lease = OfficeLease.create!(
        operator: @operator,
        location: @location,
        organization: organizations(:sierra_nevada_organization),
        office: offices(:office_23b),
        subscription: subscriptions(:cowork_tahoe_office_lease),
        start_date: 1.year.ago,
        end_date: 1.year.from_now,
      )
      lease.update_column(:organization_id, nil) # orphaned rows exist in prod

      assert_equal base, @report.revenue_for_period(range: range)
    end

    private

    def most_recent_past_weekday
      day = Date.current - 1
      day -= 1 while day.on_weekend?
      day
    end

    def most_recent_past_saturday
      day = Date.current - 1
      day -= 1 until day.saturday?
      day
    end

    # A dedicated room sidesteps overlap conflicts with fixture reservations.
    def utilization_room
      @utilization_room ||= Room.create!(
        name: "Utilization Test Room #{SecureRandom.hex(3)}",
        operator: @operator,
        location: @location,
        visible: true,
        capacity: 4,
      )
    end

    def book_room(datetime_in:, minutes:)
      Reservation.create!(
        user: users(:cowork_tahoe_member),
        room: utilization_room,
        datetime_in: datetime_in,
        minutes: minutes,
        cancelled: false,
      )
    end

    def create_day_pass(day:)
      member = users(:cowork_tahoe_member)
      DayPass.create!(
        day: day,
        user: member,
        billable: member,
        operator: @operator,
        location: @location,
        day_pass_type: day_pass_type(:cowork_tahoe_day_pass_type),
      )
    end

    def create_subscription(user:, plan:, active:)
      Subscription.create!(
        plan: plan,
        subscribable: user,
        billable: user,
        active: active,
        pending: false,
        start_date: 6.months.ago,
      )
    end

    # The office-lease subscription fixture's `plan:` label doesn't resolve to
    # a real plans.yml entry (fixtures hash labels without checking), so the
    # lease's plan_id dangles and lease_supplement_for_month sees no plan.
    def repoint_lease_fixture_plan
      subscriptions(:cowork_tahoe_office_lease)
        .update_columns(plan_id: plans(:cowork_tahoe_office_lease_plan).id)
    end

    def paid_invoice_dollars(range)
      Invoice.for_location(@location).paid
        .where("COALESCE(invoices.due_date, invoices.date) BETWEEN ? AND ?",
          range.begin.beginning_of_day, range.end.end_of_day)
        .sum(:amount_due).to_f / 100.0
    end

    def create_paid_invoice(billable:, amount_cents:, date:, due_date: nil)
      Invoice.create!(
        billable: billable,
        operator: @operator,
        location: @location,
        amount_due: amount_cents,
        amount_paid: amount_cents,
        status: "paid",
        date: date,
        due_date: due_date,
      )
    end

    def create_member(organization:, out_of_band:)
      suffix = SecureRandom.hex(4)
      User.create!(
        name: "Inactive Tester #{suffix}",
        email: "inactive-#{suffix}@example.com",
        password: "password123",
        admin_created: true,
        operator: @operator,
        original_location: @location,
        current_location: @location,
        organization: organization,
        out_of_band: out_of_band,
        approved: true,
        archived: false,
        role: User::UNASSIGNED,
        marketing_suppressed: false,
      )
    end
  end
end
