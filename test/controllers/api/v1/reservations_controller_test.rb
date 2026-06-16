require "test_helper"

# Coverage for team (org-mate) booking visibility — so a member can see what
# their organization already has reserved and not double-book.
class Api::V1::ReservationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @operator = operators(:cowork_tahoe)
    @viewer   = users(:cowork_tahoe_admin)    # in sierra_nevada_organization
    @mate     = users(:other_location_admin)  # same org
    @room     = rooms(:small_meeting_room)
    @room.reservations.delete_all             # clean slate to avoid fixture overlaps
  end

  def headers(user)
    token = JWT.encode(
      { user_id: user.id, operator_id: @operator.id, exp: 30.days.from_now.to_i },
      Rails.application.secret_key_base, "HS256",
    )
    { "Authorization" => "Bearer #{token}", "X-Operator-Subdomain" => @operator.subdomain, "Content-Type" => "application/json" }
  end

  test "index returns org-mates' upcoming bookings in `team`, labeled, excluding self/past/cancelled" do
    mate_future    = Reservation.create!(user: @mate,   room: @room, datetime_in: 2.days.from_now, minutes: 60)
    mate_past      = Reservation.create!(user: @mate,   room: @room, datetime_in: 2.days.ago,      minutes: 60)
    mate_cancelled = Reservation.create!(user: @mate,   room: @room, datetime_in: 5.days.from_now, minutes: 60, cancelled: true)
    own_future     = Reservation.create!(user: @viewer, room: @room, datetime_in: 3.days.from_now, minutes: 60)

    get "/api/v1/reservations", headers: headers(@viewer)
    assert_response :success
    body = JSON.parse(response.body)
    team_ids = body["team"].map { |r| r["id"] }

    assert_includes team_ids, mate_future.id,    "org-mate's upcoming booking should appear in team"
    refute_includes team_ids, mate_past.id,      "past excluded"
    refute_includes team_ids, mate_cancelled.id, "cancelled excluded"
    refute_includes team_ids, own_future.id,     "your own booking is not in team"

    assert_equal @mate.name, body["team"].find { |r| r["id"] == mate_future.id }["booked_by"]
    assert_includes body["upcoming"].map { |r| r["id"] }, own_future.id, "own booking still in upcoming"
  end

  test "index `team` is empty when the user has no organization" do
    @viewer.update_column(:organization_id, nil)
    Reservation.create!(user: @mate, room: @room, datetime_in: 2.days.from_now, minutes: 60)
    get "/api/v1/reservations", headers: headers(@viewer)
    assert_response :success
    assert_equal [], JSON.parse(response.body)["team"]
  end

  test "room availability flags org-mate bookings as teammate (for the picker)" do
    date = 4.days.from_now.to_date
    Reservation.create!(user: @mate, room: @room, datetime_in: date.to_time.change(hour: 10), minutes: 60)

    get "/api/v1/rooms/#{@room.id}/availability", params: { date: date.to_s }, headers: headers(@viewer)
    assert_response :success
    row = JSON.parse(response.body)["reservations"].find { |r| r["user"] == @mate.name }
    refute_nil row
    assert_equal true,  row["is_teammate"], "org-mate booking should be flagged is_teammate"
    assert_equal false, row["mine"]
  end

  # --- PATCH /api/v1/reservations/:id (edit an upcoming reservation) ----------

  test "update moves an upcoming reservation's start time and duration" do
    res = Reservation.create!(user: @viewer, room: @room, datetime_in: 2.days.from_now.change(hour: 10, min: 0), minutes: 60)
    new_start = 3.days.from_now.change(hour: 14, min: 0)

    patch "/api/v1/reservations/#{res.id}",
      params: { reservation: { datetime_in: new_start.iso8601, minutes: 90 } }.to_json,
      headers: headers(@viewer)

    assert_response :success
    res.reload
    assert_equal 90, res.minutes
    assert_equal new_start.to_i, res.start_at.to_i, "start moved to the requested instant"
    assert_equal 90, JSON.parse(response.body)["minutes"]
  end

  test "update can change duration alone, keeping the same start" do
    start = 2.days.from_now.change(hour: 9, min: 0)
    res = Reservation.create!(user: @viewer, room: @room, datetime_in: start, minutes: 60)

    patch "/api/v1/reservations/#{res.id}",
      params: { reservation: { datetime_in: start.iso8601, minutes: 30 } }.to_json,
      headers: headers(@viewer)

    assert_response :success
    assert_equal 30, res.reload.minutes
  end

  test "update rejects a move that overlaps a different reservation" do
    res     = Reservation.create!(user: @viewer, room: @room, datetime_in: 2.days.from_now.change(hour: 10), minutes: 60)
    blocker = Reservation.create!(user: @mate,   room: @room, datetime_in: 4.days.from_now.change(hour: 13), minutes: 60)

    patch "/api/v1/reservations/#{res.id}",
      params: { reservation: { datetime_in: blocker.datetime_in.iso8601, minutes: 60 } }.to_json,
      headers: headers(@viewer)

    assert_response :unprocessable_entity
    assert_match(/conflict/i, JSON.parse(response.body)["error"])
    # Original window is untouched on failure.
    assert_equal 60, res.reload.minutes
    assert_equal 2.days.from_now.change(hour: 10).to_i, res.start_at.to_i
  end

  test "update lets a reservation keep its own slot (overlap excludes self)" do
    start = 2.days.from_now.change(hour: 11, min: 0)
    res = Reservation.create!(user: @viewer, room: @room, datetime_in: start, minutes: 60)

    # Same start, longer — only conflicts with itself, which is allowed.
    patch "/api/v1/reservations/#{res.id}",
      params: { reservation: { datetime_in: start.iso8601, minutes: 120 } }.to_json,
      headers: headers(@viewer)

    assert_response :success
    assert_equal 120, res.reload.minutes
  end

  test "update refuses a reservation that has already started" do
    res = Reservation.create!(user: @viewer, room: @room, datetime_in: 30.minutes.ago, minutes: 120)

    patch "/api/v1/reservations/#{res.id}",
      params: { reservation: { datetime_in: 1.hour.from_now.iso8601, minutes: 60 } }.to_json,
      headers: headers(@viewer)

    assert_response :unprocessable_entity
    assert_equal 120, res.reload.minutes
  end

  test "update rejects a non-positive duration" do
    res = Reservation.create!(user: @viewer, room: @room, datetime_in: 2.days.from_now.change(hour: 10), minutes: 60)

    patch "/api/v1/reservations/#{res.id}",
      params: { reservation: { datetime_in: res.datetime_in.iso8601, minutes: 0 } }.to_json,
      headers: headers(@viewer)

    assert_response :unprocessable_entity
    assert_equal 60, res.reload.minutes
  end

  test "update 404s for another user's reservation" do
    other = Reservation.create!(user: @mate, room: @room, datetime_in: 2.days.from_now.change(hour: 10), minutes: 60)

    patch "/api/v1/reservations/#{other.id}",
      params: { reservation: { datetime_in: 3.days.from_now.iso8601, minutes: 60 } }.to_json,
      headers: headers(@viewer)

    assert_response :not_found
  end

  test "update can move a reservation to a different available room" do
    other_room = rooms(:large_meeting_room) # also at the operator, free
    other_room.reservations.delete_all
    res = Reservation.create!(user: @viewer, room: @room, datetime_in: 2.days.from_now.change(hour: 10), minutes: 60)

    patch "/api/v1/reservations/#{res.id}",
      params: { reservation: { room_id: other_room.id, datetime_in: res.datetime_in.iso8601, minutes: 60 } }.to_json,
      headers: headers(@viewer)

    assert_response :success
    assert_equal other_room.id, res.reload.room_id
  end

  test "update rejects a room change that collides on the new room" do
    other_room = rooms(:large_meeting_room)
    other_room.reservations.delete_all
    res     = Reservation.create!(user: @viewer, room: @room,      datetime_in: 2.days.from_now.change(hour: 10), minutes: 60)
    blocker = Reservation.create!(user: @mate,   room: other_room, datetime_in: 2.days.from_now.change(hour: 10), minutes: 60)

    patch "/api/v1/reservations/#{res.id}",
      params: { reservation: { room_id: other_room.id, datetime_in: res.datetime_in.iso8601, minutes: 60 } }.to_json,
      headers: headers(@viewer)

    assert_response :unprocessable_entity
    assert_equal @room.id, res.reload.room_id
  end
end
