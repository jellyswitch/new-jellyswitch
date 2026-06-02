require "test_helper"

# Coverage for GET /api/v1/rooms/:id/pricing — the endpoint the mobile
# ReserveNow / ReserveLater screens hit to quote a meeting-room booking.
#
# Bug: for a PRICED (premium) room the endpoint quoted the full hourly
# charge to admins/owners (and any user who is never charged at booking
# time), because it computed the price straight from hourly_rate without
# consulting should_charge_for_reservation?. The reservation *create*
# path already exempts these users (paid = should_charge && rate > 0), so
# they were shown a charge and a payment step for a room that books free.
#
# The fix mirrors #reserve_now: exempt users get a free, included quote.
class Api::V1::RoomsPricingTest < ActionDispatch::IntegrationTest
  setup do
    @operator = operators(:cowork_tahoe)
    # Force the production billing path so should_charge_for_reservation?
    # evaluates the real member/admin exemptions rather than the blanket
    # "never charge outside production" short-circuit.
    @operator.update!(billing_state: "production")

    @admin       = users(:cowork_tahoe_admin)
    @non_member  = users(:cowork_tahoe_non_member)
    @priced_room = rooms(:large_meeting_room)
    @priced_room.update!(hourly_rate_in_cents: 5000) # $50/hr premium room
  end

  def token_for(user)
    JWT.encode(
      { user_id: user.id, operator_id: @operator.id, exp: 30.days.from_now.to_i },
      Rails.application.secret_key_base,
      "HS256",
    )
  end

  def headers_for(user)
    {
      "Authorization"        => "Bearer #{token_for(user)}",
      "X-Operator-Subdomain" => @operator.subdomain,
      "Content-Type"         => "application/json",
    }
  end

  test "admin/owner is not quoted a charge for a priced premium room" do
    get "/api/v1/rooms/#{@priced_room.id}/pricing",
        params: { date: Date.current.to_s, minutes: 60 },
        headers: headers_for(@admin)

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal 0, body["estimated_cost"],
      "an admin/owner must not be quoted an hourly charge for a premium room"
    assert body["included_in_plan"],
      "an admin/owner's premium-room booking should read as included/free"
  end

  test "a non-exempt user is still quoted the full hourly charge for a priced room" do
    get "/api/v1/rooms/#{@priced_room.id}/pricing",
        params: { date: Date.current.to_s, minutes: 60 },
        headers: headers_for(@non_member)

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal 5000, body["estimated_cost"],
      "a guest with no coverage must still be charged the hourly rate"
    assert_not body["included_in_plan"]
  end
end
