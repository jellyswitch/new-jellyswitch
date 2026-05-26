require "test_helper"

class Api::V1::BeaconsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @member   = users(:cowork_tahoe_member)
    @operator = operators(:cowork_tahoe)
    @beacon   = beacons(:cowork_tahoe_front_door_beacon)

    @token = JWT.encode(
      { user_id: @member.id, operator_id: @operator.id, exp: 30.days.from_now.to_i },
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

  test "heartbeat updates last_seen_at and battery_pct for known beacons" do
    @beacon.update!(last_seen_at: 2.hours.ago, battery_pct: 80)
    started_at = Time.current

    post "/api/v1/beacons/heartbeat",
         params:  {
           beacons: [
             { uuid: @beacon.uuid, major: @beacon.major, minor: @beacon.minor, battery_pct: 73 },
           ],
         }.to_json,
         headers: headers

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal 1, body["updated"]
    assert_equal 0, body["unknown"]

    @beacon.reload
    assert_equal 73, @beacon.battery_pct
    assert_operator @beacon.last_seen_at, :>=, started_at
  end

  test "heartbeat reports unknown beacons separately" do
    post "/api/v1/beacons/heartbeat",
         params:  {
           beacons: [
             { uuid: @beacon.uuid, major: @beacon.major, minor: @beacon.minor },
             { uuid: "00000000-0000-0000-0000-000000000000", major: 1, minor: 1 },
           ],
         }.to_json,
         headers: headers

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal 1, body["updated"]
    assert_equal 1, body["unknown"]
  end

  test "empty beacon list returns zero counts" do
    post "/api/v1/beacons/heartbeat",
         params:  { beacons: [] }.to_json,
         headers: headers

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal 0, body["updated"]
    assert_equal 0, body["unknown"]
  end

  test "missing auth returns 401" do
    post "/api/v1/beacons/heartbeat",
         params:  { beacons: [] }.to_json,
         headers: { "Content-Type" => "application/json" }

    assert_response :unauthorized
  end
end
