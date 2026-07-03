require "test_helper"

# Coverage for /api/v1/admin/reservations (the all-bookings list the
# mobile admin's Reservations screen calls). Same regression as
# Api::V1::Admin::MembersController#reservations: the JSON didn't
# include `ended_early`, so the screen rendered ended-early bookings
# identically to active ones AND offered Extend/Cancel buttons on
# finished reservations.
class Api::V1::Admin::ReservationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin    = users(:cowork_tahoe_admin)
    @operator = operators(:cowork_tahoe)
    @member   = users(:cowork_tahoe_member)

    @token = JWT.encode(
      { user_id: @admin.id, operator_id: @operator.id, exp: 30.days.from_now.to_i },
      Rails.application.secret_key_base,
      "HS256",
    )
  end

  def headers
    {
      "Authorization"        => "Bearer #{@token}",
      "X-Operator-Subdomain" => @operator.subdomain,
      "Content-Type"         => "application/json",
    }
  end

  test "index payload includes ended_early so the all-bookings list can badge it" do
    # The "room_reservation_today" fixture's <%= Time.zone.today %> lands
    # at the prior PDT day after YAML/timestamptz conversion, so the
    # controller's `today` scope skips it. Pin datetime_in explicitly.
    reservations(:room_reservation_today).update!(
      ended_early: true,
      datetime_in: Time.zone.now.change(hour: 10),
    )

    get "/api/v1/admin/reservations", params: { scope: "today" }, headers: headers
    assert_response :success

    body = JSON.parse(response.body)
    match = body.find { |r| r["id"] == reservations(:room_reservation_today).id }
    refute_nil match, "expected the ended-early reservation in today's scope"
    assert_equal true, match["ended_early"],
      "ended_early must be surfaced or the admin all-bookings list can't distinguish from active rows"
  end

  test "index payload includes ended_early=false for active bookings" do
    reservations(:room_reservation_today).update!(
      ended_early: false,
      datetime_in: Time.zone.now.change(hour: 10),
    )

    get "/api/v1/admin/reservations", params: { scope: "today" }, headers: headers
    assert_response :success

    body = JSON.parse(response.body)
    match = body.find { |r| r["id"] == reservations(:room_reservation_today).id }
    refute_nil match
    assert_equal false, match["ended_early"]
  end

  test "admin can create a reservation for a member in a free, available room" do
    locations(:cowork_tahoe_location).update!(credits_enabled: false)
    room = rooms(:small_meeting_room) # visible, rentable, free
    when_time = 1.day.from_now.change(hour: 14, min: 0, sec: 0)

    post "/api/v1/admin/reservations",
      params: {
        user_id: @member.id,
        room_id: room.id,
        datetime_in: when_time.iso8601,
        minutes: 60,
      }.to_json,
      headers: headers

    assert_response :created
  end

  # When the booking is rejected, the admin must see WHY. The create action
  # used to render `result.error` — but the billing interactors fail with
  # `context.message`, so every failure collapsed to the generic
  # "Booking failed", hiding (e.g.) an overlap conflict from the admin.
  test "create surfaces the real failure reason instead of a generic message" do
    locations(:cowork_tahoe_location).update!(credits_enabled: false)
    room = rooms(:small_meeting_room)
    when_time = 1.day.from_now.change(hour: 14, min: 0, sec: 0)

    # Pre-book the room for that exact window so the admin's booking conflicts.
    Reservation.create!(user: @member, room: room, datetime_in: when_time, minutes: 60)

    post "/api/v1/admin/reservations",
      params: {
        user_id: @member.id,
        room_id: room.id,
        datetime_in: when_time.iso8601,
        minutes: 60,
      }.to_json,
      headers: headers

    assert_response :unprocessable_entity
    assert_match(/is no longer free/i, JSON.parse(response.body)["error"])
  end
end
