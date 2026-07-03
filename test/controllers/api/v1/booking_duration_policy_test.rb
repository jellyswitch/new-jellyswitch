require "test_helper"

# One duration policy everywhere (the web-admin-8h vs mobile-admin-12h drift):
# staff book up to 12h on any room; members/visitors get 12h on PRICED rooms
# ("book the conference room for a day") and keep 4h on free rooms.
class BookingDurationPolicyTest < ActionDispatch::IntegrationTest
  setup do
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
    @member   = users(:cowork_tahoe_member)
    @admin    = users(:cowork_tahoe_admin)
    @free_room = rooms(:small_meeting_room)
    @conference = rooms(:large_meeting_room)
    # credit_cost: 0 — the fixture's credit pricing would 422 on balance,
    # which is orthogonal to the duration policy under test.
    @conference.update!(rentable: true, hourly_rate_in_cents: 4000, credit_cost: 0)
    Reservation.where(room: [@free_room, @conference]).delete_all
    @zone = ActiveSupport::TimeZone[@location.time_zone]
    day = Date.current + 7
    @start = @zone.local(day.year, day.month, day.day, 6)
  end

  def headers_for(user)
    token = JWT.encode({ user_id: user.id, operator_id: @operator.id, exp: 30.days.from_now.to_i },
                       Rails.application.secret_key_base, "HS256")
    { "Authorization" => "Bearer #{token}",
      "X-Operator-Subdomain" => @operator.subdomain,
      "Content-Type" => "application/json" }
  end

  def book(user, room, minutes)
    post "/api/v1/reservations",
         params: { reservation: { room_id: room.id,
                                  datetime_in: @start.strftime("%Y-%m-%dT%H:%M:%S"),
                                  minutes: minutes } }.to_json,
         headers: headers_for(user)
  end

  test "Room#max_bookable_minutes encodes the policy" do
    assert_equal 720, @free_room.max_bookable_minutes(admin: true)
    assert_equal 720, @conference.max_bookable_minutes(admin: false)
    assert_equal 240, @free_room.max_bookable_minutes(admin: false)
  end

  test "member booking a priced conference room for 12 hours succeeds" do
    book(@member, @conference, 720)
    assert_response :created
  end

  test "member booking a free room beyond 4 hours is rejected with a clear message" do
    book(@member, @free_room, 300)
    assert_response :unprocessable_entity
    assert_match(/up to 4 hours/, JSON.parse(response.body)["error"])
  end

  test "member booking a priced room beyond 12 hours is rejected" do
    book(@member, @conference, 750)
    assert_response :unprocessable_entity
    assert_match(/up to 12 hours/, JSON.parse(response.body)["error"])
  end

  test "staff may book a free room up to 12 hours" do
    book(@admin, @free_room, 720)
    assert_response :created
  end

  test "rooms#available drops free rooms beyond the 4h cap for members" do
    get "/api/v1/rooms/available",
        params: { date: (Date.current + 7).to_s, time: "06:00", minutes: 300 },
        headers: headers_for(@member)
    assert_response :success
    body = JSON.parse(response.body)
    all_ids = (body["available_rooms"] + body["unavailable_rooms"]).map { |r| r["id"] }
    refute_includes all_ids, @free_room.id, "free rooms are not bookable >4h by members"
    assert_includes body["available_rooms"].map { |r| r["id"] }, @conference.id
  end

  test "rooms#available keeps free rooms beyond 4h for staff" do
    get "/api/v1/rooms/available",
        params: { date: (Date.current + 7).to_s, time: "06:00", minutes: 300 },
        headers: headers_for(@admin)
    assert_response :success
    assert_includes JSON.parse(response.body)["available_rooms"].map { |r| r["id"] }, @free_room.id
  end
end
