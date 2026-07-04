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
