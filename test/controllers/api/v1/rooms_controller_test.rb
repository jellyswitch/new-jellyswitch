require "test_helper"

# End-to-end coverage for /api/v1/rooms*. This is the reservation entry point
# from mobile; a regression here is what surfaced Coleen's RecordNotFound bug
# last week. Tests focus on: auth gating, location/visibility scoping, the
# 15-minute time_slots structure, the superadmin 24h window, and the pricing
# response shape for the common subscriber and no-coverage paths.
class Api::V1::RoomsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @operator   = operators(:cowork_tahoe)
    @location   = locations(:cowork_tahoe_location)
    @user       = users(:cowork_tahoe_member)
    @superadmin = users(:cowork_tahoe_superadmin)
    @room       = rooms(:small_meeting_room)

    @token = JWT.encode(
      { user_id: @user.id, operator_id: @operator.id, exp: 30.days.from_now.to_i },
      Rails.application.secret_key_base,
      "HS256",
    )
    @auth = { "Authorization" => "Bearer #{@token}", "X-Operator-Subdomain" => @operator.subdomain }

    @superadmin_token = JWT.encode(
      { user_id: @superadmin.id, operator_id: @operator.id, exp: 30.days.from_now.to_i },
      Rails.application.secret_key_base,
      "HS256",
    )
    @superadmin_auth = { "Authorization" => "Bearer #{@superadmin_token}", "X-Operator-Subdomain" => @operator.subdomain }
  end

  # ---------- GET /api/v1/rooms ----------

  test "index without a token returns 401" do
    get "/api/v1/rooms"
    assert_response :unauthorized
  end

  test "index returns visible rooms scoped to the user's current location" do
    get "/api/v1/rooms", headers: @auth

    assert_response :success
    body = JSON.parse(response.body)
    assert body.is_a?(Array)
    ids = body.map { |r| r["id"] }
    assert_includes ids, @room.id
    body.each do |r|
      %w[id name capacity hourly_rate amenities rentable available].each do |key|
        assert r.key?(key), "expected room JSON to include #{key.inspect}"
      end
    end
  end

  test "index excludes hidden rooms" do
    @room.update!(visible: false)

    get "/api/v1/rooms", headers: @auth

    assert_response :success
    ids = JSON.parse(response.body).map { |r| r["id"] }
    refute_includes ids, @room.id,
      "hidden room #{@room.id} leaked into /api/v1/rooms"
  end

  # ---------- GET /api/v1/rooms/:id/time_slots ----------

  test "time_slots without a token returns 401" do
    get "/api/v1/rooms/#{@room.id}/time_slots"
    assert_response :unauthorized
  end

  test "time_slots returns 15-minute slots with the expected fields" do
    # Pick a far-future date so the today-floor branch doesn't truncate slots.
    date = (Date.current + 30).to_s

    get "/api/v1/rooms/#{@room.id}/time_slots",
        params: { date: date },
        headers: @auth

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal @room.id, body.dig("room", "id")
    assert_equal date,     body["date"]

    slots = body.fetch("slots")
    assert slots.any?, "expected at least one slot for a future date"
    slots.each do |s|
      %w[time hour label available].each { |k| assert s.key?(k), "slot missing #{k.inspect}" }
    end

    # Slots are quarter-hour increments and stay within the location's working window.
    minutes = slots.map { |s| s["time"].split(":").last.to_i }
    assert (minutes - [0, 15, 30, 45]).empty?, "all slot minutes must be 0/15/30/45, got #{minutes.uniq}"

    hours = slots.map { |s| s["hour"] }
    assert hours.min >= 6,  "earliest slot hour should be >= working_day_start (6), got #{hours.min}"
    assert hours.max <  20, "latest slot hour should be <  working_day_end (20), got #{hours.max}"
  end

  test "time_slots gives superadmins a 24-hour window" do
    date = (Date.current + 30).to_s

    get "/api/v1/rooms/#{@room.id}/time_slots",
        params: { date: date },
        headers: @superadmin_auth

    assert_response :success
    hours = JSON.parse(response.body).fetch("slots").map { |s| s["hour"] }
    assert_equal 0,  hours.min, "superadmin window should start at hour 0"
    assert_equal 23, hours.max, "superadmin window should reach hour 23"
  end

  # ---------- GET /api/v1/rooms/:id/pricing ----------

  test "pricing without a token returns 401" do
    get "/api/v1/rooms/#{@room.id}/pricing"
    assert_response :unauthorized
  end

  test "pricing returns the expected shape for an active subscriber" do
    # cowork_tahoe_member has an active full-time subscription per fixtures,
    # so they should not be prompted to buy a day pass.
    date = (Date.current + 1).to_s

    get "/api/v1/rooms/#{@room.id}/pricing",
        params: { date: date, minutes: 60 },
        headers: @auth

    assert_response :success
    body = JSON.parse(response.body)
    %w[charge_type estimated_cost source needs_day_pass].each do |k|
      assert body.key?(k), "pricing response missing #{k.inspect}"
    end
    assert_equal false, body["needs_day_pass"],
      "active subscriber should not be prompted for a day pass"
  end

  test "pricing flags needs_day_pass for a user with no coverage" do
    # The cowork_tahoe_member fixture is covered three ways: a personal
    # subscription, the org's subscription, and the org's OfficeLease.
    # Strip all three so the controller falls through to the no-coverage
    # branch. (Day pass would also count, but the fixture has none.)
    @user.subscriptions.update_all(active: false)
    @user.organization&.subscriptions&.update_all(active: false)
    OfficeLease.where(organization: @user.organization).update_all(end_date: 2.days.ago)

    date = (Date.current + 1).to_s

    get "/api/v1/rooms/#{@room.id}/pricing",
        params: { date: date, minutes: 60 },
        headers: @auth

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal true, body["needs_day_pass"],
      "uncovered member booking a free-rate room should be prompted for a day pass — got source=#{body['source']}, charge_type=#{body['charge_type']}"
  end
end
