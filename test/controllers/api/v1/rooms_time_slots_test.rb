require "test_helper"

# Coverage for GET /api/v1/rooms/:id/time_slots — the endpoint the mobile
# Reserve Later / Reserve Now screens hit to build the bookable time picker.
#
# Bug (Drew Bray, Cowork Tahoe, 2026-06): a subscribed member picked a 5:30 PM
# start to book a conference room into the evening, but the picker only offered
# slots up to the location's posted close (working_day_end), so the duration
# silently capped at 30 minutes and he could not book 6–8 PM. Members are meant
# to have 24/7 access; posted working hours should bound non-members only.
#
# Fix mirrors the existing superadmin bypass: a member (active subscription or
# lease at the location) gets the full 24h window of start slots; non-members
# stay bounded by working_day_start/end.
class Api::V1::RoomsTimeSlotsTest < ActionDispatch::IntegrationTest
  setup do
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
    # Posted hours: open 06:00, close 20:00 (8 PM). Evening slots past 20:00
    # only appear for members once the bypass is in place.
    @location.update!(working_day_start: "06:00", working_day_end: "20:00")

    @room = rooms(:large_meeting_room) # lives at cowork_tahoe_location
    @member     = users(:cowork_tahoe_member)
    @non_member = users(:cowork_tahoe_non_member)

    # has_active_subscription_at_location? joins through plan.location, so the
    # member's plan must be scoped to this location for the bypass to fire.
    plans(:cowork_tahoe_full_time_plan).update!(location_id: @location.id)

    # A clearly future date avoids the "skip past slots for today" trimming.
    @date = (Date.current + 7).to_s
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

  def slot_hours(user)
    get "/api/v1/rooms/#{@room.id}/time_slots",
        params: { date: @date },
        headers: headers_for(user)
    assert_response :success
    JSON.parse(response.body).fetch("slots").map { |s| s["hour"] }
  end

  test "a member is offered evening slots past the posted close time" do
    hours = slot_hours(@member)

    assert hours.include?(21),
      "a member should be able to start a booking at 9 PM, well past the 8 PM close"
    assert_equal 23, hours.max,
      "a member's last bookable start should reach late evening (23:45), not the 8 PM close"
  end

  test "a non-member is still bounded by the posted working hours" do
    hours = slot_hours(@non_member)

    assert hours.max < 20,
      "a non-member's last start slot must fall before the 8 PM close, got hour #{hours.max}"
  end
end
