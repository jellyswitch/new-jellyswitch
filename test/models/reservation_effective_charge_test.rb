require "test_helper"

# Reservation#effective_charge_in_cents — the display charge used by the admin
# feeds (web FeedItems::Reservation component + mobile FeedController). It must
# surface a day-pass / subscription meeting-room overage on a FREE room, where
# charge_amount (room rate × minutes) is $0, without under-reporting paid rooms.
class ReservationEffectiveChargeTest < ActiveSupport::TestCase
  setup do
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
  end

  # A member with no other reservations, so ChargeCalculator's prior-usage sum
  # is clean (the cowork_tahoe_member fixture already has same-day bookings).
  def fresh_member
    create(:user, operator: @operator, original_location: @location, current_location: @location)
  end

  test "day-pass overage on a free room is reflected even with no hold/capture yet" do
    ActsAsTenant.with_tenant(@operator) do
      member = fresh_member
      # Overage RATE is location-scoped now (ADR 0012); the day-pass type only
      # defines the included allowance.
      @location.update!(overage_rate_in_cents: 6000)
      room = create(:room, operator: @operator, location: @location, hourly_rate_in_cents: 0)
      dpt  = create(:day_pass_type, operator: @operator, location: @location,
                    included_meeting_room_minutes: 60, overage_rate_in_cents: 0)
      reservation = create(:reservation, user: member, room: room, minutes: 120, paid: true)
      create(:day_pass, user: member, billable: member, day: reservation.datetime_in.to_date,
             day_pass_type: dpt, operator: @operator, location: @location)

      # 120 used − 60 included = 60 min over; location $60/hr ⇒ 6000¢
      assert_equal 6000, reservation.effective_charge_in_cents
    end
  end

  test "paid room reports its booked price (room rate × minutes)" do
    ActsAsTenant.with_tenant(@operator) do
      member = fresh_member
      room = create(:room, operator: @operator, location: @location, hourly_rate_in_cents: 6000)
      reservation = create(:reservation, user: member, room: room, minutes: 60, paid: true)

      assert_equal 6000, reservation.effective_charge_in_cents
    end
  end

  test "settled capture wins when present" do
    ActsAsTenant.with_tenant(@operator) do
      member = fresh_member
      room = create(:room, operator: @operator, location: @location, hourly_rate_in_cents: 0)
      reservation = create(:reservation, user: member, room: room, minutes: 120, paid: true,
                           captured_amount_in_cents: 4200)

      assert_equal 4200, reservation.effective_charge_in_cents
    end
  end

  test "free reservation with no overage is zero" do
    ActsAsTenant.with_tenant(@operator) do
      member = fresh_member
      room = create(:room, operator: @operator, location: @location, hourly_rate_in_cents: 0)
      reservation = create(:reservation, user: member, room: room, minutes: 30, paid: false)

      assert_equal 0, reservation.effective_charge_in_cents
    end
  end

  # ADR 0026: a Day Office hold is a $0 posted-hours reservation minted BY the
  # office pass purchase — it must never draw down a meeting-room allowance
  # itself. Without the day_office_pass_id exclusion in ChargeCalculator's
  # day_pass_overage_cents, the hold's own ~600 minutes would eat the very
  # allowance the pass grants, pricing an otherwise-covered booking as overage.
  test "a day-pass holder's own office hold doesn't eat their meeting-room allowance (ADR 0026)" do
    ActsAsTenant.with_tenant(@operator) do
      member = fresh_member
      # A non-zero overage rate matters here: at the default $0/min ANY overage
      # minute count prices at 0 too, which would let this test pass even if
      # the exclusion regressed. $60/hr makes 30 leaked minutes price at 3000¢.
      @location.update!(working_day_start: "08:00", working_day_end: "18:00", overage_rate_in_cents: 6000)
      office_type = create(:day_pass_type, operator: @operator, location: @location,
                           kind: "day_office", included_meeting_room_minutes: 60)
      pool_room = create(:room, operator: @operator, location: @location,
                         hourly_rate_in_cents: 0, include_with_day_pass: true)
      office_type.assign_office_rooms!({ pool_room.id => 1 })
      day = Date.current + 7
      office_pass = create(:day_pass, user: member, billable: member, operator: @operator,
                           location: @location, day_pass_type: office_type, day: day)
      hold = DayOffices::Allocator.allocate!(day_pass: office_pass)
      assert_equal 600, hold.minutes # sanity: a regression here would silently defeat the assertion below

      other_room = create(:room, operator: @operator, location: @location,
                          hourly_rate_in_cents: 0, include_with_day_pass: true)
      booking = create(:reservation, user: member, room: other_room,
                       datetime_in: day.in_time_zone.change(hour: 8), minutes: 30)

      # 30 requested <= 60 included ⇒ free, IF the hold's 600 min are excluded.
      assert_equal 0, Billing::Reservations::ChargeCalculator.call(reservation: booking, minutes: 30)
    end
  end

  # Subscription twin of the test above: the same exclusion is needed in
  # ChargeCalculator's subscription_overage_cents, whose usage sum (unlike the
  # day-pass one) carries no room filter at all — so an uncounted-for office
  # hold blows straight through any plan's included-minutes pool.
  test "a member's own office hold doesn't eat their subscription meeting-room allowance (ADR 0026)" do
    ActsAsTenant.with_tenant(@operator) do
      member = fresh_member
      @location.update!(working_day_start: "08:00", working_day_end: "18:00")
      plan = create(:plan, operator: @operator, location: @location,
                    included_meeting_room_minutes: 120, overage_rate_in_cents: 6000)
      create(:subscription, plan: plan, subscribable: member, billable: member, start_date: 5.days.ago)

      # No meeting-room limit on the office TYPE itself, so ChargeCalculator's
      # day-pass branch doesn't intercept — this isolates the subscription path.
      office_type = create(:day_pass_type, operator: @operator, location: @location, kind: "day_office")
      pool_room = create(:room, operator: @operator, location: @location, hourly_rate_in_cents: 0)
      office_type.assign_office_rooms!({ pool_room.id => 1 })
      day = Date.current + 7
      office_pass = create(:day_pass, user: member, billable: member, operator: @operator,
                           location: @location, day_pass_type: office_type, day: day)
      hold = DayOffices::Allocator.allocate!(day_pass: office_pass)
      assert_equal 600, hold.minutes

      other_room = create(:room, operator: @operator, location: @location, hourly_rate_in_cents: 0)
      booking = create(:reservation, user: member, room: other_room,
                       datetime_in: day.in_time_zone.change(hour: 8), minutes: 30)

      assert_equal 0, Billing::Reservations::ChargeCalculator.call(reservation: booking, minutes: 30)
    end
  end

  # The hold itself must never be charged — not even against its OWN type's
  # included-minutes allowance. Without the early return, pricing the hold
  # (e.g. via effective_charge_in_cents on an admin feed card) excludes it
  # from the usage sum via `where.not(id: reservation.id)` but then prices its
  # own 600 minutes as overage past the 60-minute allowance: 540 min × $60/hr
  # = $540, a bogus charge on a $0 hold (ADR 0026).
  test "the hold itself is never charged, even against its own type's included minutes (ADR 0026)" do
    ActsAsTenant.with_tenant(@operator) do
      member = fresh_member
      @location.update!(working_day_start: "08:00", working_day_end: "18:00", overage_rate_in_cents: 6000)
      office_type = create(:day_pass_type, operator: @operator, location: @location,
                           kind: "day_office", included_meeting_room_minutes: 60)
      pool_room = create(:room, operator: @operator, location: @location,
                         hourly_rate_in_cents: 0, include_with_day_pass: true)
      office_type.assign_office_rooms!({ pool_room.id => 1 })
      day = Date.current + 7
      office_pass = create(:day_pass, user: member, billable: member, operator: @operator,
                           location: @location, day_pass_type: office_type, day: day)
      hold = DayOffices::Allocator.allocate!(day_pass: office_pass)
      assert_equal 600, hold.minutes

      assert_equal 0, Billing::Reservations::ChargeCalculator.call(reservation: hold, minutes: hold.minutes)
    end
  end
end
