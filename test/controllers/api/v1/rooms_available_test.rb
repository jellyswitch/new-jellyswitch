require "test_helper"

class Api::V1::RoomsAvailableTest < ActionDispatch::IntegrationTest
  setup do
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
    @user     = users(:cowork_tahoe_member)
    @room     = rooms(:small_meeting_room) # at cowork_tahoe_location
    @room.reservations.delete_all
    @date     = (Date.current + 5).to_s
  end

  def headers
    token = JWT.encode({ user_id: @user.id, operator_id: @operator.id, exp: 30.days.from_now.to_i },
                       Rails.application.secret_key_base, "HS256")
    { "Authorization" => "Bearer #{token}", "X-Operator-Subdomain" => @operator.subdomain }
  end

  test "lists a free room as available for the window" do
    get "/api/v1/rooms/available", params: { date: @date, time: "09:00", minutes: 60 }, headers: headers
    assert_response :success
    body = JSON.parse(response.body)
    ids = body["available_rooms"].map { |r| r["id"] }
    assert_includes ids, @room.id
    assert_equal false, body["no_rooms_available"]
  end

  test "a room booked for the window is unavailable" do
    start = Date.parse(@date).in_time_zone(@location.time_zone).change(hour: 9)
    Reservation.create!(user: @user, room: @room, datetime_in: start, minutes: 60)

    get "/api/v1/rooms/available", params: { date: @date, time: "09:00", minutes: 60 }, headers: headers
    assert_response :success
    body = JSON.parse(response.body)
    refute_includes body["available_rooms"].map { |r| r["id"] }, @room.id
    assert_includes body["unavailable_rooms"].map { |r| r["id"] }, @room.id
  end

  test "exclude_reservation_id frees the edited reservation's own room" do
    start = Date.parse(@date).in_time_zone(@location.time_zone).change(hour: 9)
    res = Reservation.create!(user: @user, room: @room, datetime_in: start, minutes: 60)

    get "/api/v1/rooms/available",
        params: { date: @date, time: "09:00", minutes: 60, exclude_reservation_id: res.id },
        headers: headers
    assert_response :success
    assert_includes JSON.parse(response.body)["available_rooms"].map { |r| r["id"] }, @room.id
  end

  test "returns 422 for a malformed time" do
    get "/api/v1/rooms/available", params: { date: @date, time: "25:99", minutes: 60 }, headers: headers
    assert_response :unprocessable_entity
  end

  test "returns 422 for a blank time" do
    get "/api/v1/rooms/available", params: { date: @date, minutes: 60 }, headers: headers
    assert_response :unprocessable_entity
  end

  # --- include_hidden (admin-only carveout, e.g. Choose Folsom's auditorium) ---

  def admin_headers
    token = JWT.encode({ user_id: users(:cowork_tahoe_superadmin).id, operator_id: @operator.id, exp: 30.days.from_now.to_i },
                       Rails.application.secret_key_base, "HS256")
    { "Authorization" => "Bearer #{token}", "X-Operator-Subdomain" => @operator.subdomain }
  end

  def hidden_room!
    Room.create!(name: "Auditorium", operator: @operator, location: @location,
                 visible: false, rentable: true, hourly_rate_in_cents: 0, capacity: 50)
  end

  test "hidden rooms are excluded by default even for an admin" do
    room = hidden_room!
    get "/api/v1/rooms/available", params: { date: @date, time: "09:00", minutes: 60 }, headers: admin_headers
    assert_response :success
    refute_includes JSON.parse(response.body)["available_rooms"].map { |r| r["id"] }, room.id
  end

  test "include_hidden surfaces hidden rooms for an admin" do
    room = hidden_room!
    get "/api/v1/rooms/available", params: { date: @date, time: "09:00", minutes: 60, include_hidden: true }, headers: admin_headers
    assert_response :success
    assert_includes JSON.parse(response.body)["available_rooms"].map { |r| r["id"] }, room.id
  end

  test "include_hidden is ignored for non-admins" do
    room = hidden_room!
    get "/api/v1/rooms/available", params: { date: @date, time: "09:00", minutes: 60, include_hidden: true }, headers: headers
    assert_response :success
    refute_includes JSON.parse(response.body)["available_rooms"].map { |r| r["id"] }, room.id
  end

  # --- should_charge in pricing_context ---
  # The when-first room list computes each room's price client-side from
  # pricing_context. For a PRICED room an exempt user (admin/member/
  # leaseholder) books free, but the list showed the hourly charge because
  # pricing_context carried no should_charge signal — only subscriber_unlimited.
  # Mirror #reserve_now: surface should_charge so the chips read Free.
  test "pricing_context carries should_charge=false for an exempt user" do
    @operator.update!(billing_state: "production")
    admin = users(:cowork_tahoe_admin)
    token = JWT.encode({ user_id: admin.id, operator_id: @operator.id, exp: 30.days.from_now.to_i },
                       Rails.application.secret_key_base, "HS256")
    get "/api/v1/rooms/available", params: { date: @date, time: "09:00", minutes: 60 },
        headers: { "Authorization" => "Bearer #{token}", "X-Operator-Subdomain" => @operator.subdomain }
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal false, body.dig("pricing_context", "should_charge"),
      "an admin/owner must read as exempt so priced rooms show Free in the list"
  end

  test "pricing_context carries should_charge=true for a non-exempt user" do
    @operator.update!(billing_state: "production")
    non_member = users(:cowork_tahoe_non_member)
    token = JWT.encode({ user_id: non_member.id, operator_id: @operator.id, exp: 30.days.from_now.to_i },
                       Rails.application.secret_key_base, "HS256")
    get "/api/v1/rooms/available", params: { date: @date, time: "09:00", minutes: 60 },
        headers: { "Authorization" => "Bearer #{token}", "X-Operator-Subdomain" => @operator.subdomain }
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal true, body.dig("pricing_context", "should_charge"),
      "a non-member must still be charged the hourly rate for a priced room"
  end
end
