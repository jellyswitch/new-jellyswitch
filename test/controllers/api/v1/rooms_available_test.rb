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

  test "archived rooms never surface, even for an admin with include_hidden" do
    room = Room.create!(name: "Retired Room", operator: @operator, location: @location,
                        archived: true, rentable: true, capacity: 4)
    get "/api/v1/rooms/available", params: { date: @date, time: "09:00", minutes: 60, include_hidden: true }, headers: admin_headers
    assert_response :success
    body = JSON.parse(response.body)
    all_ids = (body["available_rooms"] + body["unavailable_rooms"]).map { |r| r["id"] }
    refute_includes all_ids, room.id
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

  # --- non-member room visibility + day-pass label (Book a Room funnel) ---
  # An uncovered prospect sees every room they can pay their way into: priced
  # (rentable) rooms plus $0 include_with_day_pass rooms. A $0 room a day pass
  # does NOT unlock stays hidden — showing it would invert the same confusion
  # the funnel change fixes. The included room's list label names the pass
  # price so the label and ADR 0019's buy-prompt can never disagree.

  def non_member_headers
    token = JWT.encode({ user_id: users(:cowork_tahoe_non_member).id, operator_id: @operator.id, exp: 30.days.from_now.to_i },
                       Rails.application.secret_key_base, "HS256")
    { "Authorization" => "Bearer #{token}", "X-Operator-Subdomain" => @operator.subdomain }
  end

  def booth!
    Room.create!(name: "Phone Booth", operator: @operator, location: @location, capacity: 1,
                 include_with_day_pass: true, rentable: false, hourly_rate_in_cents: 0)
  end

  def sellable_pass!(cents = 4000)
    DayPassType.create!(operator: @operator, location: @location, name: "Coworking Day Pass",
                        amount_in_cents: cents, visible: true, available: true,
                        included_meeting_room_minutes: 180)
  end

  test "a non-member sees day-pass-included rooms but not member-only or unrentable priced rooms" do
    @operator.update!(billing_state: "production")
    booth = booth!
    members_only = Room.create!(name: "Members Lounge", operator: @operator, location: @location,
                                capacity: 2, rentable: false, hourly_rate_in_cents: 0)
    fishbowl = Room.create!(name: "Fishbowl", operator: @operator, location: @location,
                            capacity: 4, rentable: false, hourly_rate_in_cents: 2500)

    get "/api/v1/rooms/available", params: { date: @date, time: "09:00", minutes: 60 }, headers: non_member_headers
    assert_response :success
    ids = JSON.parse(response.body)["available_rooms"].map { |r| r["id"] }
    assert_includes ids, booth.id
    refute_includes ids, members_only.id
    refute_includes ids, fishbowl.id
  end

  test "included room label names the day-pass price for an uncovered user" do
    @operator.update!(billing_state: "production")
    booth = booth!
    sellable_pass!(4000)

    get "/api/v1/rooms/available", params: { date: @date, time: "09:00", minutes: 60 }, headers: non_member_headers
    assert_response :success
    room = JSON.parse(response.body)["available_rooms"].find { |r| r["id"] == booth.id }
    assert_equal "Included with $40 day pass", room.dig("charge", "label")
    assert_equal 0, room.dig("charge", "cents")
    assert_equal true, room["include_with_day_pass"]
  end

  test "non-whole-dollar pass prices keep their cents in the label" do
    @operator.update!(billing_state: "production")
    booth = booth!
    sellable_pass!(3750)

    get "/api/v1/rooms/available", params: { date: @date, time: "09:00", minutes: 60 }, headers: non_member_headers
    room = JSON.parse(response.body)["available_rooms"].find { |r| r["id"] == booth.id }
    assert_equal "Included with $37.50 day pass", room.dig("charge", "label")
  end

  test "included room label falls back to Day pass required when no pass is sellable" do
    @operator.update!(billing_state: "production")
    booth = booth!
    DayPassType.where(operator: @operator).update_all(visible: false)

    get "/api/v1/rooms/available", params: { date: @date, time: "09:00", minutes: 60 }, headers: non_member_headers
    room = JSON.parse(response.body)["available_rooms"].find { |r| r["id"] == booth.id }
    assert_equal "Day pass required", room.dig("charge", "label")
  end

  test "a member still sees member-only rooms" do
    @operator.update!(billing_state: "production")
    members_only = Room.create!(name: "Members Lounge", operator: @operator, location: @location,
                                capacity: 2, rentable: false, hourly_rate_in_cents: 0)

    get "/api/v1/rooms/available", params: { date: @date, time: "09:00", minutes: 60 }, headers: headers
    assert_response :success
    ids = JSON.parse(response.body)["available_rooms"].map { |r| r["id"] }
    assert_includes ids, members_only.id
  end
end
