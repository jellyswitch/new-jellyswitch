require "test_helper"

class Api::V1::AutoUnlocksControllerTest < ActionDispatch::IntegrationTest
  setup do
    @member     = users(:cowork_tahoe_member)
    @non_member = users(:cowork_tahoe_non_member)
    @operator   = operators(:cowork_tahoe)
    @location   = locations(:cowork_tahoe_location)
    @beacon     = beacons(:cowork_tahoe_front_door_beacon)
    @door       = Door.create!(
      name:        "Cowork Tahoe Front",
      slug:        "ct-front-#{SecureRandom.hex(4)}",
      location:    @location,
      operator:    @operator,
      kisi_id:     12345,
      available:   true,
    )
    @beacon.update!(door: @door)

    @member_token     = jwt_for(@member)
    @non_member_token = jwt_for(@non_member)

    @kisi_url = "https://api.kisi.io/locks/#{@door.kisi_id}/unlock"
    stub_request(:post, @kisi_url).to_return(
      status:  200,
      body:    { success: true, lock_id: @door.kisi_id }.to_json,
      headers: { "Content-Type" => "application/json" },
    )

    Rails.cache.clear
  end

  def jwt_for(user)
    JWT.encode(
      { user_id: user.id, operator_id: @operator.id, exp: 30.days.from_now.to_i },
      Rails.application.secret_key_base,
      "HS256",
    )
  end

  def headers(token = @member_token)
    {
      "Authorization"        => "Bearer #{token}",
      "X-Operator-Subdomain" => @operator.subdomain,
      "Content-Type"         => "application/json",
    }
  end

  def payload(overrides = {})
    {
      uuid:  @beacon.uuid,
      major: @beacon.major,
      minor: @beacon.minor,
      nonce: SecureRandom.hex(16),
    }.merge(overrides)
  end

  test "active member triggers Kisi unlock and logs auto DoorPunch" do
    assert_difference -> { DoorPunch.where(method: "auto").count }, 2 do
      post "/api/v1/door/auto_unlock",
           params:  payload.to_json,
           headers: headers
    end

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal true,         body["success"]
    assert_equal @door.name,   body["door"]
    assert_requested :post, @kisi_url, times: 1
  end

  test "non-member is denied without calling Kisi" do
    post "/api/v1/door/auto_unlock",
         params:  payload.to_json,
         headers: headers(@non_member_token)

    assert_response :forbidden
    body = JSON.parse(response.body)
    assert_equal false, body["success"]
    assert_not_requested :post, @kisi_url
    assert_equal 0, DoorPunch.where(method: "auto").count
  end

  test "unknown beacon returns 404" do
    post "/api/v1/door/auto_unlock",
         params:  payload(uuid: "00000000-0000-0000-0000-000000000000").to_json,
         headers: headers

    assert_response :not_found
    assert_not_requested :post, @kisi_url
  end

  test "beacon without an assigned door returns 422" do
    @beacon.update!(door: nil)

    post "/api/v1/door/auto_unlock",
         params:  payload.to_json,
         headers: headers

    assert_response :unprocessable_entity
    assert_not_requested :post, @kisi_url
  end

  test "replayed nonce is rejected with 409" do
    body = payload

    post "/api/v1/door/auto_unlock", params: body.to_json, headers: headers
    assert_response :success

    post "/api/v1/door/auto_unlock", params: body.to_json, headers: headers
    assert_response :conflict
    assert_requested :post, @kisi_url, times: 1
  end

  test "missing nonce returns 422" do
    post "/api/v1/door/auto_unlock",
         params:  payload(nonce: "").to_json,
         headers: headers

    assert_response :unprocessable_entity
    assert_not_requested :post, @kisi_url
  end

  test "missing auth returns 401" do
    post "/api/v1/door/auto_unlock",
         params:  payload.to_json,
         headers: { "Content-Type" => "application/json" }

    assert_response :unauthorized
  end
end
