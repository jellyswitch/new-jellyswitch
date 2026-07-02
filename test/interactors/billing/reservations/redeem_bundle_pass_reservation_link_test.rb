require "test_helper"

class Billing::Reservations::RedeemBundlePassReservationLinkTest < ActiveSupport::TestCase
  test "the minted bundle pass is linked to the reservation" do
    operator = operators(:cowork_tahoe); location = locations(:cowork_tahoe_location)
    ActsAsTenant.with_tenant(operator) do
      user = create(:user, operator: operator, original_location: location, current_location: location)
      room = create(:room, operator: operator, location: location, hourly_rate_in_cents: 0, include_with_day_pass: true)
      dpt  = create(:day_pass_type, operator: operator, location: location, included_meeting_room_minutes: 60)
      DayPassBundle.create!(user: user, operator: operator, location: location, day_pass_type: dpt,
                            quantity_purchased: 5, passes_remaining: 5, purchased_at: Time.current)
      res  = create(:reservation, user: user, room: room, minutes: 60, datetime_in: (Date.current + 2).to_time + 9.hours)

      result = Billing::Reservations::RedeemBundlePass.call(reservation: res, user: user, use_bundle_pass: true)
      assert_equal :redeemed, result.outcome
      assert_equal res.id, result.bundle_redemption_day_pass.reservation_id
    end
  end
end
