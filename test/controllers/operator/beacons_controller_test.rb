require "test_helper"

class Operator::BeaconsControllerTest < ActionDispatch::IntegrationTest
  setup do
    setup_initial_user_fixtures
    @location  = locations(:cowork_tahoe_location)
    @operator  = operators(:cowork_tahoe)
    @admin     = users(:cowork_tahoe_admin)
    @member    = users(:cowork_tahoe_member)
    @beacon    = beacons(:cowork_tahoe_front_door_beacon)
  end

  test "admin can see the beacons index" do
    log_in @admin
    get beacons_path, env: default_env
    assert_response :success
    assert_includes response.body, @beacon.name
  end

  test "member cannot see the beacons index" do
    log_in @member
    get beacons_path, env: default_env
    # Pundit's NotAuthorizedError handler redirects to root rather than 403.
    assert_response :redirect
  end

  # Regression: when a Pundit-denied page is reached with a Referer equal to
  # that same page (reload / Turbo nav), the denial handler used to redirect
  # back to the Referer — i.e. straight back to the denied page — producing an
  # infinite 302 loop (ERR_TOO_MANY_REDIRECTS, prod incident on /beacons for a
  # location with door integration disabled). It must redirect to root instead.
  test "denied page does not redirect back to itself (no redirect loop)" do
    log_in @member
    get beacons_path, env: default_env.merge("HTTP_REFERER" => "https://tml.jellyswitch.com#{beacons_path}")
    assert_response :redirect
    assert_redirected_to root_path
    assert_no_match %r{/beacons}, response.headers["Location"].to_s
  end

  test "admin can create a beacon" do
    log_in @admin
    assert_difference -> { Beacon.count }, 1 do
      post beacons_path,
           params: { beacon: {
             name:  "Side Entry",
             uuid:  "11111111-2222-3333-4444-555555555555",
             major: 2,
             minor: 2,
           } },
           env: default_env
    end
    new_beacon = Beacon.find_by(name: "Side Entry")
    assert_equal @location.id, new_beacon.location_id
    assert_equal @operator.id, new_beacon.operator_id
  end

  test "admin cannot create a beacon with invalid major" do
    log_in @admin
    assert_no_difference -> { Beacon.count } do
      post beacons_path,
           params: { beacon: {
             name:  "Bad Major",
             uuid:  "deadbeef-0000-0000-0000-000000000000",
             major: 99_999,
             minor: 1,
           } },
           env: default_env
      assert_response :unprocessable_entity
    end
  end

  test "admin can edit a beacon" do
    log_in @admin
    patch beacon_path(@beacon),
          params: { beacon: { name: "Renamed Front" } },
          env: default_env
    assert_equal "Renamed Front", @beacon.reload.name
  end

  test "destroy soft-archives the beacon" do
    log_in @admin
    delete beacon_path(@beacon), env: default_env
    assert_equal false, @beacon.reload.available
  end

  test "unarchive flips available back to true" do
    @beacon.update!(available: false)
    log_in @admin
    post beacon_unarchive_path(beacon_id: @beacon.id), env: default_env
    assert_equal true, @beacon.reload.available
  end

  test "archived index only shows soft-deleted beacons" do
    @beacon.update!(available: false)
    log_in @admin
    get archived_beacons_path, env: default_env
    assert_response :success
    assert_includes response.body, @beacon.name
  end
end
