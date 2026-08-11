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
    @location = locations(:cowork_tahoe_location)
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

  def token_for(user)
    JWT.encode(
      { user_id: user.id, operator_id: user.operator_id, exp: 30.days.from_now.to_i },
      Rails.application.secret_key_base,
      "HS256",
    )
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

  # A room in a second location of the same operator — one the fixture staff
  # (all scoped to cowork_tahoe_location) do not manage.
  def create_other_location_room
    @location_b = Geocoder.stub(:search, ->(*_) { [] }) do
      ActsAsTenant.with_tenant(@operator) { create(:location, operator: @operator) }
    end
    ActsAsTenant.with_tenant(@operator) do
      create(:room, operator: @operator, location: @location_b)
    end
  end

  # A future reservation in that second location.
  def create_other_location_reservation
    Reservation.create!(
      user: @member,
      room: create_other_location_room,
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

  # --- Cross-tenant / cross-location guard on create --------------------------
  #
  # create looked the room up with a bare Room.find. acts_as_scopable's
  # default_scope reads RequestStore, which nothing in the API stack sets, so
  # the lookup was completely unscoped — an operator-X admin could book (and
  # charge their member for) a room belonging to a different OPERATOR, one
  # level worse than the destroy/extend location hole above. The lookup now
  # goes through the tenant association plus the same allowed_location_ids
  # set as find_reservation.

  def create_other_operator_room
    other_operator = create(:operator)
    other_location = Geocoder.stub(:search, ->(*_) { [] }) do
      ActsAsTenant.with_tenant(other_operator) { create(:location, operator: other_operator) }
    end
    ActsAsTenant.with_tenant(other_operator) do
      create(:room, operator: other_operator, location: other_location)
    end
  end

  test "create rejects a room belonging to another operator" do
    room = create_other_operator_room

    assert_no_difference -> { Reservation.unscoped.count } do
      post "/api/v1/admin/reservations",
        params: {
          user_id: @member.id,
          room_id: room.id,
          datetime_in: 1.day.from_now.change(hour: 14, min: 0, sec: 0).iso8601,
          minutes: 60,
        }.to_json,
        headers: headers
    end

    assert_response :not_found
  end

  test "community manager cannot create a booking at a location they do not manage" do
    room_b = create_other_location_room
    cm = users(:cowork_tahoe_community_manager)
    refute cm.managed_location_ids.include?(@location_b.id), "fixture CM must not manage location B"

    assert_no_difference -> { Reservation.unscoped.count } do
      post "/api/v1/admin/reservations",
        params: {
          user_id: @member.id,
          room_id: room_b.id,
          datetime_in: 1.day.from_now.change(hour: 14, min: 0, sec: 0).iso8601,
          minutes: 60,
        }.to_json,
        headers: headers_for(cm)
    end

    assert_response :not_found
  end

  test "superadmin can create a booking at any location within their operator" do
    room_b = create_other_location_room
    # Keep the free room out of the day-pass coverage chain — the boundary
    # under test is the room lookup, not ADR 0019 coverage.
    room_b.update!(include_with_day_pass: false)
    owner = users(:cowork_tahoe_superadmin)
    refute owner.managed_location_ids.include?(@location_b.id),
      "success below must be the superadmin bypass, not a management row"

    post "/api/v1/admin/reservations",
      params: {
        user_id: @member.id,
        room_id: room_b.id,
        datetime_in: 1.day.from_now.change(hour: 14, min: 0, sec: 0).iso8601,
        minutes: 60,
      }.to_json,
      headers: headers_for(owner)

    assert_response :created
  end

  # --- Location scope on the list endpoints -----------------------------------
  #
  # index/calendar listed reservations operator-wide, so a location-scoped
  # community manager saw other locations' bookings (member names, times)
  # that — after the destroy/extend fix above — they could no longer act on.
  # The web all-bookings list is current_location-scoped and never showed
  # them. Non-superadmins are now confined to allowed_location_ids;
  # superadmins keep the operator-wide view.

  test "index confines non-superadmin staff to locations they manage" do
    other = create_other_location_reservation
    mine = Reservation.create!(
      user: @member,
      room: rooms(:small_meeting_room),
      datetime_in: 2.days.from_now.change(hour: 12, min: 0, sec: 0),
      minutes: 60,
    )
    cm = users(:cowork_tahoe_community_manager)

    get "/api/v1/admin/reservations", params: { scope: "upcoming" }, headers: headers_for(cm)

    assert_response :success
    ids = JSON.parse(response.body).map { |r| r["id"] }
    assert_includes ids, mine.id, "managed-location booking must still be listed"
    refute_includes ids, other.id, "other location's booking must not leak into the list"
  end

  test "index keeps the operator-wide view for superadmins" do
    other = create_other_location_reservation
    owner = users(:cowork_tahoe_superadmin)

    get "/api/v1/admin/reservations", params: { scope: "upcoming" }, headers: headers_for(owner)

    assert_response :success
    ids = JSON.parse(response.body).map { |r| r["id"] }
    assert_includes ids, other.id
  end

  test "calendar confines non-superadmin staff to locations they manage" do
    other = create_other_location_reservation
    mine = Reservation.create!(
      user: @member,
      room: rooms(:small_meeting_room),
      datetime_in: 2.days.from_now.change(hour: 12, min: 0, sec: 0),
      minutes: 60,
    )
    cm = users(:cowork_tahoe_community_manager)

    get "/api/v1/admin/reservations/calendar",
      params: { start: Time.zone.now.iso8601, end: 4.days.from_now.iso8601 },
      headers: headers_for(cm)

    assert_response :success
    ids = JSON.parse(response.body).map { |r| r["id"] }
    assert_includes ids, mine.id, "managed-location booking must still be on the calendar"
    refute_includes ids, other.id, "other location's booking must not leak into the calendar"
  end

  # --- reassign_room / reassign_options (Task 12, ADR 0026) -----------------

  # Builds a live Day Office hold under @operator/@location and returns
  # [hold, room_a, room_b] — Allocator fills position order, so the hold
  # always lands on room_a first (mirrors DayOffices::ReassignRoomTest).
  def make_office_hold(user: @member, day: 3.days.from_now.to_date)
    hold = nil
    room_a = room_b = nil
    ActsAsTenant.with_tenant(@operator) do
      _bundle, room_a, room_b = make_office_bundle(member: user)
      pass = DayPass.create!(user: user, billable: user, operator: @operator, location: @location,
                             day_pass_type: _bundle.day_pass_type, day: day, imported: true)
      hold = DayOffices::Allocator.allocate!(day_pass: pass)
    end
    [hold, room_a, room_b]
  end

  test "reassign_room moves the hold and returns the new room's name" do
    hold, room_a, room_b = make_office_hold
    assert_equal room_a, hold.room

    patch "/api/v1/admin/reservations/#{hold.id}/reassign_room",
      params: { room_id: room_b.id }.to_json, headers: headers

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal true, body["success"]
    assert_equal room_b.name, body["room"]
    assert_equal room_b, hold.reload.room
  end

  test "reassign_room returns 422 when the target room is already booked for that window" do
    hold, room_a, room_b = make_office_hold
    Reservation.create!(user: users(:cowork_tahoe_non_member), room: room_b,
                        datetime_in: hold.datetime_in, minutes: hold.minutes)

    patch "/api/v1/admin/reservations/#{hold.id}/reassign_room",
      params: { room_id: room_b.id }.to_json, headers: headers

    assert_response :unprocessable_entity
    assert_match(/already booked/i, JSON.parse(response.body)["error"])
    assert_equal room_a, hold.reload.room
  end

  test "reassign_room returns 422 for a reservation that is not a Day Office hold" do
    ordinary = reservations(:future_room_reservation)
    target_room = rooms(:small_meeting_room)

    patch "/api/v1/admin/reservations/#{ordinary.id}/reassign_room",
      params: { room_id: target_room.id }.to_json, headers: headers

    assert_response :unprocessable_entity
    assert_match(/not a day office hold/i, JSON.parse(response.body)["error"])
  end

  test "reassign_room 404s on a reservation belonging to another operator" do
    other_operator = Operator.create!(name: "Other Space", subdomain: "otherspace-reassign-test")
    other_location = create(:location, operator: other_operator)
    foreign_room = Room.create!(name: "Foreign Room", operator: other_operator, location: other_location)
    foreign_reservation = Reservation.create!(user: users(:cowork_tahoe_member), room: foreign_room,
                                              datetime_in: 1.day.from_now, minutes: 60)

    patch "/api/v1/admin/reservations/#{foreign_reservation.id}/reassign_room",
      params: { room_id: foreign_room.id }.to_json, headers: headers

    assert_response :not_found
  end

  test "reassign_room returns 422 for a cancelled (released) hold instead of a bare 404" do
    hold, room_a, room_b = make_office_hold
    hold.update_columns(cancelled: true)

    patch "/api/v1/admin/reservations/#{hold.id}/reassign_room",
      params: { room_id: room_b.id }.to_json, headers: headers

    assert_response :unprocessable_entity
    assert_match(/no longer active/i, JSON.parse(response.body)["error"])
  end

  test "reassign_room is forbidden for a non-admin (member) token" do
    hold, room_a, room_b = make_office_hold
    member_headers = headers.merge("Authorization" => "Bearer #{token_for(@member)}")

    patch "/api/v1/admin/reservations/#{hold.id}/reassign_room",
      params: { room_id: room_b.id }.to_json, headers: member_headers

    assert_response :forbidden
    assert_equal room_a, hold.reload.room
  end

  test "reassign_options 404s on a reservation belonging to another operator" do
    other_operator = Operator.create!(name: "Other Space 2", subdomain: "otherspace-reassign-options-test")
    other_location = create(:location, operator: other_operator)
    foreign_room = Room.create!(name: "Foreign Room 2", operator: other_operator, location: other_location)
    foreign_reservation = Reservation.create!(user: users(:cowork_tahoe_member), room: foreign_room,
                                              datetime_in: 1.day.from_now, minutes: 60)

    get "/api/v1/admin/reservations/#{foreign_reservation.id}/reassign_options", headers: headers

    assert_response :not_found
  end

  test "reassign_options returns 422 for a cancelled (released) hold instead of a bare 404" do
    hold, room_a, room_b = make_office_hold
    hold.update_columns(cancelled: true)

    get "/api/v1/admin/reservations/#{hold.id}/reassign_options", headers: headers

    assert_response :unprocessable_entity
    assert_match(/no longer active/i, JSON.parse(response.body)["error"])
  end

  test "reassign_options lists free rooms, flags hidden, and excludes the current/occupied/archived rooms" do
    hold, room_a, _room_b = make_office_hold
    hidden_room = occupied_room = archived_room = nil
    ActsAsTenant.with_tenant(@operator) do
      hidden_room   = Room.create!(name: "Hidden Office", operator: @operator, location: @location, visible: false)
      occupied_room = Room.create!(name: "Occupied Office", operator: @operator, location: @location)
      archived_room = Room.create!(name: "Archived Office", operator: @operator, location: @location, archived: true)
    end
    Reservation.create!(user: users(:cowork_tahoe_non_member), room: occupied_room,
                        datetime_in: hold.datetime_in, minutes: hold.minutes)

    get "/api/v1/admin/reservations/#{hold.id}/reassign_options", headers: headers

    assert_response :success
    body = JSON.parse(response.body)
    ids = body.map { |r| r["id"] }

    assert_includes ids, hidden_room.id, "a hidden room must still be offered to an admin"
    hidden_entry = body.find { |r| r["id"] == hidden_room.id }
    assert_equal true, hidden_entry["hidden"]

    refute_includes ids, room_a.id, "the hold's current room must not be offered as a target"
    refute_includes ids, occupied_room.id
    refute_includes ids, archived_room.id
  end

  test "reassign_options returns an error for a reservation that is not a Day Office hold" do
    ordinary = reservations(:future_room_reservation)

    get "/api/v1/admin/reservations/#{ordinary.id}/reassign_options", headers: headers

    assert_response :unprocessable_entity
    assert_match(/not a day office hold/i, JSON.parse(response.body)["error"])
  end

  # --- Cross-location guard on the reassign endpoints -------------------------
  #
  # Both reassign actions resolve through find_reservation, so they inherit the
  # boundary #717 put on destroy/extend and must be held to it: staff can
  # neither MOVE a hold nor ENUMERATE rooms for one at a location they don't
  # manage. reassign_options matters as much as reassign_room — it leaks the
  # room inventory and occupancy of a location the caller has no business
  # seeing. Superadmins keep the operator-wide reach.
  #
  # NOTE the operator WEB reassign action is deliberately wider than this (it
  # is tenant-scoped, so the profile page can list a member's holds across
  # every location) — see the reassign_room comment in
  # Operator::ReservationsController.

  # A live Day Office hold in a second location of the same operator — one the
  # fixture staff (all scoped to cowork_tahoe_location) do not manage. Points
  # @location at location B first: make_office_hold builds the day-pass type,
  # room pool and pass ambiently off @location, same as the tests above.
  # Returns [hold, room_a, room_b], with the hold allocated to room_a.
  def make_other_location_office_hold
    @location_b = Geocoder.stub(:search, ->(*_) { [] }) do
      ActsAsTenant.with_tenant(@operator) { create(:location, operator: @operator) }
    end
    @location = @location_b
    make_office_hold
  end

  test "community manager cannot reassign a hold at a location they do not manage" do
    hold, room_a, room_b = make_other_location_office_hold
    cm = users(:cowork_tahoe_community_manager)
    refute cm.managed_location_ids.include?(@location_b.id), "fixture CM must not manage location B"

    patch "/api/v1/admin/reservations/#{hold.id}/reassign_room",
      params: { room_id: room_b.id }.to_json, headers: headers_for(cm)

    assert_response :not_found
    assert_equal room_a, hold.reload.room, "cross-location reassign must not move the hold"
  end

  test "community manager cannot list reassign options for a hold at a location they do not manage" do
    hold, _room_a, _room_b = make_other_location_office_hold
    cm = users(:cowork_tahoe_community_manager)
    refute cm.managed_location_ids.include?(@location_b.id), "fixture CM must not manage location B"

    get "/api/v1/admin/reservations/#{hold.id}/reassign_options", headers: headers_for(cm)

    assert_response :not_found
  end

  test "superadmin can reassign a hold across locations within their operator" do
    hold, _room_a, room_b = make_other_location_office_hold
    owner = users(:cowork_tahoe_superadmin)
    refute owner.managed_location_ids.include?(@location_b.id),
      "success below must be the superadmin bypass, not a management row"

    patch "/api/v1/admin/reservations/#{hold.id}/reassign_room",
      params: { room_id: room_b.id }.to_json, headers: headers_for(owner)

    assert_response :success
    assert_equal room_b, hold.reload.room
  end
end
