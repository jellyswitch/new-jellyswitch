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
end
