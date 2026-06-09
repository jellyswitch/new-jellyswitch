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
end
