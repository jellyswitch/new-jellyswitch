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

  # --- Cross-location guard on the mutating actions ---------------------------
  #
  # destroy/extend used to scope the reservation lookup to the operator tenant
  # only (rooms.operator_id), so a community manager homed at one location
  # could cancel or extend another location's bookings — something the web
  # equivalents (Reservation.for_location_id(current_location) + Pundit
  # admin_or_manager?) never allowed. Same class as the cross-surface guard
  # audit. Non-superadmins must now 404 outside their managed/home locations.

  def headers_for(user)
    token = JWT.encode(
      { user_id: user.id, operator_id: @operator.id, exp: 30.days.from_now.to_i },
      Rails.application.secret_key_base,
      "HS256",
    )
    {
      "Authorization"        => "Bearer #{token}",
      "X-Operator-Subdomain" => @operator.subdomain,
      "Content-Type"         => "application/json",
    }
  end

  # A future reservation in a second location of the same operator — one the
  # fixture staff (all scoped to cowork_tahoe_location) do not manage.
  def create_other_location_reservation
    @location_b = Geocoder.stub(:search, ->(*_) { [] }) do
      ActsAsTenant.with_tenant(@operator) { create(:location, operator: @operator) }
    end
    room_b = ActsAsTenant.with_tenant(@operator) do
      create(:room, operator: @operator, location: @location_b)
    end
    Reservation.create!(
      user: @member,
      room: room_b,
      datetime_in: 2.days.from_now.change(hour: 10, min: 0, sec: 0),
      minutes: 60,
    )
  end

  test "community manager cannot cancel a reservation at a location they do not manage" do
    reservation = create_other_location_reservation
    cm = users(:cowork_tahoe_community_manager)
    refute cm.managed_location_ids.include?(@location_b.id), "fixture CM must not manage location B"

    delete "/api/v1/admin/reservations/#{reservation.id}", headers: headers_for(cm)

    assert_response :not_found
    refute reservation.reload.cancelled, "cross-location cancel must not go through"
  end

  test "community manager cannot extend a reservation at a location they do not manage" do
    reservation = create_other_location_reservation
    cm = users(:cowork_tahoe_community_manager)

    patch "/api/v1/admin/reservations/#{reservation.id}/extend",
      params: { additional_minutes: 30 }.to_json,
      headers: headers_for(cm)

    assert_response :not_found
    assert_equal 60, reservation.reload.minutes, "cross-location extend must not change duration"
  end

  test "community manager can cancel a reservation at their managed location" do
    cm = users(:cowork_tahoe_community_manager)
    room_a = rooms(:small_meeting_room)
    assert cm.managed_location_ids.include?(room_a.location_id), "fixture CM should manage location A"
    reservation = Reservation.create!(
      user: @member,
      room: room_a,
      datetime_in: 2.days.from_now.change(hour: 10, min: 0, sec: 0),
      minutes: 60,
    )

    delete "/api/v1/admin/reservations/#{reservation.id}", headers: headers_for(cm)

    assert_response :success
    assert reservation.reload.cancelled
  end

  test "multi-location staff can cancel across the locations they manage" do
    reservation = create_other_location_reservation
    cm = users(:cowork_tahoe_community_manager)
    cm.location_managements.create!(location: @location_b)

    delete "/api/v1/admin/reservations/#{reservation.id}", headers: headers_for(cm)

    assert_response :success
    assert reservation.reload.cancelled
  end

  test "superadmin bypasses the location guard within their operator" do
    reservation = create_other_location_reservation
    owner = users(:cowork_tahoe_superadmin)
    refute owner.managed_location_ids.include?(@location_b.id),
      "success below must be the superadmin bypass, not a management row"

    delete "/api/v1/admin/reservations/#{reservation.id}", headers: headers_for(owner)

    assert_response :success
    assert reservation.reload.cancelled
  end
end
