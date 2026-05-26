require "test_helper"

# Regression coverage for the beacons array returned by GET /api/v1/me. The
# mobile app reads this at boot to know which iBeacons to start monitoring;
# missing or malformed entries cause the door-unlock-on-approach feature to
# silently no-op, so we lock the shape down here.
class Api::V1::UsersMeBeaconsTest < ActionDispatch::IntegrationTest
  setup do
    @user     = users(:cowork_tahoe_member)
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
    @door     = Door.create!(
      name:      "Cowork Tahoe Side",
      slug:      "ct-side-#{SecureRandom.hex(4)}",
      location:  @location,
      operator:  @operator,
      kisi_id:   55001,
      available: true,
    )
    @assigned_beacon = beacons(:cowork_tahoe_front_door_beacon)
    @assigned_beacon.update!(door: @door)

    @token = JWT.encode(
      { user_id: @user.id, operator_id: @operator.id, exp: 30.days.from_now.to_i },
      Rails.application.secret_key_base,
      "HS256",
    )
  end

  def get_me
    get "/api/v1/me",
        headers: { "Authorization" => "Bearer #{@token}", "X-Operator-Subdomain" => @operator.subdomain }
    JSON.parse(response.body)
  end

  test "beacons array includes available beacons that have an assigned door" do
    body = get_me
    assert_response :success

    beacons = body.fetch("beacons")
    assert_kind_of Array, beacons
    entry = beacons.find { |b| b["uuid"] == @assigned_beacon.uuid && b["major"] == @assigned_beacon.major }

    assert entry, "expected the front-door beacon in /me beacons array"
    assert_equal "beacon-#{@assigned_beacon.id}", entry["identifier"]
    assert_equal @assigned_beacon.minor, entry["minor"]
    assert_equal @door.name,              entry["door_name"]
    assert_equal @location.id,            entry["location_id"]
    assert_equal @location.name,          entry["location_name"]
  end

  test "beacons without an assigned door are excluded" do
    @assigned_beacon.update!(door: nil)
    beacons = get_me.fetch("beacons")
    refute beacons.any? { |b| b["uuid"] == @assigned_beacon.uuid },
      "beacon with no door assignment should not appear — there is no unlock target"
  end

  test "archived beacons are excluded" do
    @assigned_beacon.update!(available: false)
    beacons = get_me.fetch("beacons")
    refute beacons.any? { |b| b["uuid"] == @assigned_beacon.uuid },
      "archived beacon should not appear — admin took it out of service"
  end

  test "beacons at hidden locations are excluded" do
    hidden = Location.create!(
      name:              "Hidden Test Location",
      operator:          @operator,
      visible:           false,
      time_zone:         "Pacific Time (US & Canada)",
      working_day_start: "09:00",
      working_day_end:   "18:00",
    )
    hidden_door = Door.create!(
      name: "Hidden Door", slug: "hidden-door-#{SecureRandom.hex(4)}",
      location: hidden, operator: @operator, kisi_id: 88001, available: true,
    )
    hidden_beacon = Beacon.create!(
      name: "Hidden Front", uuid: "00000000-0000-0000-0000-AAAAAAAAAAAA",
      major: 9, minor: 9, location: hidden, operator: @operator, door: hidden_door,
    )

    beacons = get_me.fetch("beacons")
    refute beacons.any? { |b| b["uuid"] == hidden_beacon.uuid },
      "hidden-location beacon would leak the location's existence to the mobile client"
  end
end
