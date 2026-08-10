require "test_helper"

class Billing::DayPassBundles::ScheduleDayTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
  end

  def make_bundle(qty: 5, remaining: 5, expires_at: nil, created_at: Time.current)
    dpt = DayPassType.create!(operator: @operator, location: @location, name: "#{qty}-Pack",
                              amount_in_cents: 20000, quantity: qty, available: true, visible: true)
    DayPassBundle.create!(user: @member, operator: @operator, location: @location, day_pass_type: dpt,
                          quantity_purchased: qty, passes_remaining: remaining, expires_at: expires_at,
                          created_at: created_at, purchased_at: Time.current)
  end

  test "scheduling a future day mints a dated bundle-sourced pass and decrements the bundle" do
    ActsAsTenant.with_tenant(@operator) do
      @member = create(:user, operator: @operator, original_location: @location, current_location: @location)
      bundle = make_bundle(remaining: 5)
      date = Date.current + 3

      result = Billing::DayPassBundles::ScheduleDay.call(
        user: @member, location: @location, date: date, performed_by: @member)

      assert_equal :scheduled, result.outcome
      assert_equal date, result.day_pass.day
      assert_equal @location, result.day_pass.location
      assert result.day_pass.imported, "scheduled pass must be imported (no lifecycle side effects)"
      assert_equal 4, bundle.reload.passes_remaining
      assert_equal 1, bundle.redemptions.where(kind: "entry").count
      assert_equal result.day_pass.id, bundle.redemptions.where(kind: "entry").first.day_pass_id
    end
  end

  test "draws from the soonest-expiring bundle first" do
    ActsAsTenant.with_tenant(@operator) do
      @member = create(:user, operator: @operator, original_location: @location, current_location: @location)
      perpetual = make_bundle(remaining: 5, expires_at: nil)
      expiring   = make_bundle(remaining: 5, expires_at: 20.days.from_now)

      Billing::DayPassBundles::ScheduleDay.call(
        user: @member, location: @location, date: Date.current + 2, performed_by: @member)

      assert_equal 4, expiring.reload.passes_remaining, "should burn the soonest-expiring bundle"
      assert_equal 5, perpetual.reload.passes_remaining
    end
  end

  test "rejects a date already covered by an existing pass (no wasted pass)" do
    ActsAsTenant.with_tenant(@operator) do
      @member = create(:user, operator: @operator, original_location: @location, current_location: @location)
      bundle = make_bundle(remaining: 5)
      date = Date.current + 4
      create(:day_pass, user: @member, billable: @member, operator: @operator, location: @location,
             day_pass_type: bundle.day_pass_type, day: date)

      result = Billing::DayPassBundles::ScheduleDay.call(
        user: @member, location: @location, date: date, performed_by: @member)

      assert_equal :already_covered, result.outcome
      assert_equal 5, bundle.reload.passes_remaining
    end
  end

  test "rejects a past date and a date beyond the horizon" do
    ActsAsTenant.with_tenant(@operator) do
      @member = create(:user, operator: @operator, original_location: @location, current_location: @location)
      make_bundle(remaining: 5)

      past = Billing::DayPassBundles::ScheduleDay.call(
        user: @member, location: @location, date: Date.current - 1, performed_by: @member)
      assert_equal :invalid_date, past.outcome

      far = Billing::DayPassBundles::ScheduleDay.call(
        user: @member, location: @location,
        date: Date.current + Billing::DayPassBundles::ScheduleDay::HORIZON_DAYS + 1, performed_by: @member)
      assert_equal :invalid_date, far.outcome
    end
  end

  test "rejects when no passes remain" do
    ActsAsTenant.with_tenant(@operator) do
      @member = create(:user, operator: @operator, original_location: @location, current_location: @location)
      make_bundle(remaining: 0)
      result = Billing::DayPassBundles::ScheduleDay.call(
        user: @member, location: @location, date: Date.current + 1, performed_by: @member)
      assert_equal :no_bundle, result.outcome
    end
  end

  # C2: in-lock idempotency guard
  test "scheduling the same future date twice returns :already_covered the second time with only one pass burned" do
    ActsAsTenant.with_tenant(@operator) do
      @member = create(:user, operator: @operator, original_location: @location, current_location: @location)
      bundle = make_bundle(remaining: 5)
      date = Date.current + 3

      first  = Billing::DayPassBundles::ScheduleDay.call(
        user: @member, location: @location, date: date, performed_by: @member)
      second = Billing::DayPassBundles::ScheduleDay.call(
        user: @member, location: @location, date: date, performed_by: @member)

      assert_equal :scheduled,       first.outcome
      assert_equal :already_covered, second.outcome
      assert_equal 4, bundle.reload.passes_remaining, "only one pass burned for the same date"
    end
  end

  # C1: defer follow_up review email for future-date schedules
  test "scheduling a FUTURE date does NOT enqueue the follow_up email" do
    ActsAsTenant.with_tenant(@operator) do
      @member = create(:user, operator: @operator, original_location: @location, current_location: @location)
      make_bundle(remaining: 5)

      assert_no_enqueued_jobs only: SendProductEmailJob do
        Billing::DayPassBundles::ScheduleDay.call(
          user: @member, location: @location, date: Date.current + 2, performed_by: @member)
      end
    end
  end

  test "scheduling for today (same-day) DOES enqueue the follow_up email" do
    ActsAsTenant.with_tenant(@operator) do
      @member = create(:user, operator: @operator, original_location: @location, current_location: @location)
      make_bundle(remaining: 5)

      assert_enqueued_with(job: SendProductEmailJob) do
        Billing::DayPassBundles::ScheduleDay.call(
          user: @member, location: @location, date: Date.current, performed_by: @member)
      end
    end
  end

  # m2: unparseable date
  test "an unparseable date string returns :invalid_date and mints nothing" do
    ActsAsTenant.with_tenant(@operator) do
      @member = create(:user, operator: @operator, original_location: @location, current_location: @location)
      make_bundle(remaining: 5)

      result = Billing::DayPassBundles::ScheduleDay.call(
        user: @member, location: @location, date: "not-a-date", performed_by: @member)

      assert_equal :invalid_date, result.outcome
      assert_equal 0, @member.day_passes.count
    end
  end

  # m5: expiry-boundary — soonest-expiring bundle is skipped when it would be expired by the target date
  test "expiry-boundary: burns perpetual bundle for a date beyond the expiring bundle's window" do
    ActsAsTenant.with_tenant(@operator) do
      @member = create(:user, operator: @operator, original_location: @location, current_location: @location)
      expiring  = make_bundle(remaining: 5, expires_at: 10.days.from_now)
      perpetual = make_bundle(remaining: 5, expires_at: nil)

      # 5 days out — expiring bundle still valid
      result5 = Billing::DayPassBundles::ScheduleDay.call(
        user: @member, location: @location, date: Date.current + 5, performed_by: @member)
      assert_equal :scheduled, result5.outcome
      assert_equal 4, expiring.reload.passes_remaining,  "expiring bundle used for near date"
      assert_equal 5, perpetual.reload.passes_remaining

      # 15 days out — expiring bundle would be expired; must use perpetual
      result15 = Billing::DayPassBundles::ScheduleDay.call(
        user: @member, location: @location, date: Date.current + 15, performed_by: @member)
      assert_equal :scheduled, result15.outcome
      assert_equal 4, expiring.reload.passes_remaining,  "expiring bundle not touched for far date"
      assert_equal 4, perpetual.reload.passes_remaining, "perpetual bundle used for far date"
    end
  end

  test "with enforce_daily_limit, scheduling onto a full day returns :sold_out" do
    ActsAsTenant.with_tenant(@operator) do
      @member = create(:user, operator: @operator, original_location: @location, current_location: @location)
      bundle = make_bundle(remaining: 5)
      bundle.day_pass_type.update!(daily_limit: 1)
      date = Date.current + 3
      other = create(:user, operator: @operator, original_location: @location, current_location: @location)
      DayPass.create!(user: other, billable: other, operator: @operator, location: @location,
                      day_pass_type: bundle.day_pass_type, day: date, imported: true)

      result = Billing::DayPassBundles::ScheduleDay.call(
        user: @member, location: @location, date: date, performed_by: @member,
        enforce_daily_limit: true)

      assert_equal :sold_out, result.outcome
      assert_equal bundle.day_pass_type, result.day_pass_type
      assert_equal 5, bundle.reload.passes_remaining, "no pass may be burned on a sold-out day"
    end
  end

  test "without enforce_daily_limit (staff path), a full day still schedules" do
    ActsAsTenant.with_tenant(@operator) do
      @member = create(:user, operator: @operator, original_location: @location, current_location: @location)
      bundle = make_bundle(remaining: 5)
      bundle.day_pass_type.update!(daily_limit: 1)
      date = Date.current + 3
      other = create(:user, operator: @operator, original_location: @location, current_location: @location)
      DayPass.create!(user: other, billable: other, operator: @operator, location: @location,
                      day_pass_type: bundle.day_pass_type, day: date, imported: true)

      result = Billing::DayPassBundles::ScheduleDay.call(
        user: @member, location: @location, date: date, performed_by: @member)

      assert_equal :scheduled, result.outcome
      assert_equal 4, bundle.reload.passes_remaining
    end
  end

  # --- Day Office bundles (Task 10 / ADR 0026) ------------------------------
  # Scheduling from a Day Office bundle allocates a pool room the same way a
  # purchase does; the office is the point, not the access, so coverage
  # guards (subscription/lease/reservation) that would normally suppress a
  # standard-bundle mint must NOT suppress an office one. Only an existing
  # same-date pass blocks.

  # make_office_bundle / fill_office_pool! now live in test/day_office_helper.rb
  # (DayOfficeHelper, included on ActiveSupport::TestCase) — this file used to
  # carry its own copies, duplicated across four test files.

  test "scheduling a Day Office bundle day allocates a pool room" do
    ActsAsTenant.with_tenant(@operator) do
      @member = create(:user, operator: @operator, original_location: @location, current_location: @location)
      bundle, room_a, _room_b = make_office_bundle
      date = Date.current + 3

      result = Billing::DayPassBundles::ScheduleDay.call(
        user: @member, location: @location, date: date, performed_by: @member, enforce_daily_limit: true)

      assert_equal :scheduled, result.outcome
      assert result.day_pass.office_hold.present?
      assert_equal room_a, result.day_pass.office_hold.room
      assert_equal 4, bundle.reload.passes_remaining
    end
  end

  test "a member with an active subscription can still schedule an office day" do
    ActsAsTenant.with_tenant(@operator) do
      @member = users(:cowork_tahoe_member) # carries the cowork_tahoe_subscription fixture
      assert @member.has_active_subscription?, "sanity: fixture must actually carry an active subscription"
      bundle, = make_office_bundle
      date = Date.current + 3

      result = Billing::DayPassBundles::ScheduleDay.call(
        user: @member, location: @location, date: date, performed_by: @member, enforce_daily_limit: true)

      assert_equal :scheduled, result.outcome, "subscription coverage must not suppress an office mint"
      assert_equal 4, bundle.reload.passes_remaining
    end
  end

  test "a member with a reservation on the target date can still schedule an office day" do
    ActsAsTenant.with_tenant(@operator) do
      @member = create(:user, operator: @operator, original_location: @location, current_location: @location)
      bundle, = make_office_bundle
      date = Date.current + 3
      meeting_room = Room.create!(name: "Meeting Room", operator: @operator, location: @location)
      tz = ActiveSupport::TimeZone[@location.time_zone]
      Reservation.create!(user: @member, room: meeting_room,
                          datetime_in: tz.local(date.year, date.month, date.day, 10, 0), minutes: 30)

      result = Billing::DayPassBundles::ScheduleDay.call(
        user: @member, location: @location, date: date, performed_by: @member, enforce_daily_limit: true)

      assert_equal :scheduled, result.outcome, "a same-date reservation must not suppress an office mint"
      assert_equal 4, bundle.reload.passes_remaining
    end
  end

  test "an office bundle still refuses a date that already has a pass" do
    ActsAsTenant.with_tenant(@operator) do
      @member = create(:user, operator: @operator, original_location: @location, current_location: @location)
      bundle, = make_office_bundle
      date = Date.current + 4
      create(:day_pass, user: @member, billable: @member, operator: @operator, location: @location,
             day_pass_type: bundle.day_pass_type, day: date)

      result = Billing::DayPassBundles::ScheduleDay.call(
        user: @member, location: @location, date: date, performed_by: @member, enforce_daily_limit: true)

      assert_equal :already_covered, result.outcome
      assert_equal 5, bundle.reload.passes_remaining
    end
  end

  test "member self-serve strict: a sold-out office pool returns :sold_out and burns nothing" do
    ActsAsTenant.with_tenant(@operator) do
      @member = create(:user, operator: @operator, original_location: @location, current_location: @location)
      bundle, room_a, room_b = make_office_bundle
      date = Date.current + 3
      fill_office_pool!(date, room_a, room_b)

      result = Billing::DayPassBundles::ScheduleDay.call(
        user: @member, location: @location, date: date, performed_by: @member, enforce_daily_limit: true)

      assert_equal :sold_out, result.outcome
      assert_equal bundle.day_pass_type, result.day_pass_type
      assert_equal 5, bundle.reload.passes_remaining, "no pass may be burned on a sold-out office day"
      assert_equal 0, @member.day_passes.for_day(date).count, "no orphan pass row"
    end
  end

  test "staff scheduling (no enforce_daily_limit) also allocates when the pool has room" do
    ActsAsTenant.with_tenant(@operator) do
      @member = create(:user, operator: @operator, original_location: @location, current_location: @location)
      bundle, room_a, _room_b = make_office_bundle
      date = Date.current + 3

      result = Billing::DayPassBundles::ScheduleDay.call(
        user: @member, location: @location, date: date, performed_by: @member)

      assert_equal :scheduled, result.outcome
      assert_equal room_a, result.day_pass.office_hold&.room
      assert_equal 4, bundle.reload.passes_remaining
    end
  end

  test "staff scheduling (no enforce_daily_limit) succeeds office-less when the pool is full" do
    ActsAsTenant.with_tenant(@operator) do
      @member = create(:user, operator: @operator, original_location: @location, current_location: @location)
      bundle, room_a, room_b = make_office_bundle
      date = Date.current + 3
      fill_office_pool!(date, room_a, room_b)

      # Black-box, a full pool with no enforce flag looks identical to "never
      # tried to allocate at all" — spy on the call so this test can only pass
      # once staff scheduling genuinely attempts allocation (with the actual
      # minted pass, not some other row) and then falls back leniently,
      # rather than passing by coincidence.
      attempted_with = nil
      real_allocate = DayOffices::Allocator.method(:allocate!)
      result = nil
      DayOffices::Allocator.stub :allocate!, ->(**kwargs) { attempted_with = kwargs[:day_pass]; real_allocate.call(**kwargs) } do
        result = Billing::DayPassBundles::ScheduleDay.call(
          user: @member, location: @location, date: date, performed_by: @member)
      end

      assert attempted_with.present?, "staff scheduling must still attempt allocation for an office bundle"
      assert_equal :scheduled, result.outcome
      assert_equal result.day_pass.id, attempted_with.id, "allocate! must receive the pass that was actually minted"
      assert_nil result.day_pass.office_hold, "staff scheduling on a full pool is office-less by design"
      assert_equal 4, bundle.reload.passes_remaining
    end
  end

  test "a race lost inside the lock destroys the minted pass and reports :sold_out" do
    ActsAsTenant.with_tenant(@operator) do
      @member = create(:user, operator: @operator, original_location: @location, current_location: @location)
      bundle, = make_office_bundle
      date = Date.current + 3

      # The pool is genuinely free (the pre-gate above passes); the allocator
      # itself is stubbed to lose the race inside the lock — the same shape a
      # real concurrent schedule produces between that snapshot and this
      # in-lock attempt. Mirrors AllocateDayOffice's own organizer-level
      # backstop test.
      result = nil
      DayOffices::Allocator.stub :allocate!, nil do
        result = Billing::DayPassBundles::ScheduleDay.call(
          user: @member, location: @location, date: date, performed_by: @member, enforce_daily_limit: true)
      end

      assert_equal :sold_out, result.outcome
      assert_equal bundle.day_pass_type, result.day_pass_type
      assert_equal 5, bundle.reload.passes_remaining
      assert_equal 0, @member.day_passes.for_day(date).count
    end
  end

  # Quality-review fix 1 pin: the expiry-survives-the-date filter is skipped
  # entirely only for date == today (redeem_today) — it must still apply for
  # a FUTURE date, exactly like the pre-existing "expiry-boundary" test above
  # (for a standard bundle). This is the office-bundle counterpart, proving
  # the `if date > today` conditional restores the filter rather than just
  # deleting it outright.
  test "a future date past an office bundle's expiry still refuses (fix 1 preserved for future dates)" do
    ActsAsTenant.with_tenant(@operator) do
      @member = create(:user, operator: @operator, original_location: @location, current_location: @location)
      bundle, = make_office_bundle
      bundle.update!(expires_at: 5.days.from_now)
      date = Date.current + 10 # past the bundle's expiry

      result = Billing::DayPassBundles::ScheduleDay.call(
        user: @member, location: @location, date: date, performed_by: @member, enforce_daily_limit: true)

      assert_equal :no_bundle, result.outcome
      assert_equal 5, bundle.reload.passes_remaining
    end
  end
end
