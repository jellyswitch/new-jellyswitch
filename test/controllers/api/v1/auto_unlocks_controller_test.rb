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

  test "active member gets optimistic success and a pending DoorPunch" do
    assert_difference -> { DoorPunch.where(method: "auto", status: "pending").count }, 1 do
      post "/api/v1/door/auto_unlock",
           params:  payload.to_json,
           headers: headers
    end

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal true,       body["success"]
    assert_equal @door.name, body["door"]
    # Kisi now runs in KisiUnlockJob, not synchronously in the request —
    # that async hop is the whole point of the optimistic path.
    assert_not_requested :post, @kisi_url
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
    # Only the first (accepted) request created a punch; the replay is
    # rejected at the nonce gate before any unlock work.
    assert_equal 1, DoorPunch.where(method: "auto").count
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

  # ---------------------------------------------------------------------------
  # Bundle-pass consumption tests — BLE auto-unlock path
  # ---------------------------------------------------------------------------

  def bundle_user
    users(:cowork_tahoe_non_member)
  end

  def create_active_bundle(user, passes: 5)
    DayPassBundle.create!(
      user:               user,
      billable:           user,
      operator:           @operator,
      location:           @location,
      day_pass_type:      day_pass_type(:cowork_tahoe_day_pass_type),
      quantity_purchased: passes,
      passes_remaining:   passes,
      purchased_at:       Time.current,
    )
  end

  test "bundle-only user auto-unlocking burns exactly one pass" do
    user   = bundle_user
    bundle = create_active_bundle(user)
    token  = jwt_for(user)

    post "/api/v1/door/auto_unlock",
         params:  payload.to_json,
         headers: headers(token)

    assert_response :success
    assert_equal 4, bundle.reload.passes_remaining
    assert_equal 1, DayPass.where(user: user, location: @location, day: Date.current).count
  end

  test "bundle-only user auto-unlocking twice the same day burns only one pass (idempotent)" do
    user   = bundle_user
    bundle = create_active_bundle(user)
    token  = jwt_for(user)

    post "/api/v1/door/auto_unlock", params: payload.to_json, headers: headers(token)
    assert_response :success

    post "/api/v1/door/auto_unlock", params: payload(nonce: SecureRandom.hex(16)).to_json, headers: headers(token)
    assert_response :success

    assert_equal 4, bundle.reload.passes_remaining, "second entry same day must not burn again"
  end

  test "member (active subscription) auto-unlocking does NOT burn a bundle pass" do
    user   = users(:cowork_tahoe_member)
    bundle = create_active_bundle(user)
    token  = jwt_for(user)

    post "/api/v1/door/auto_unlock",
         params:  payload.to_json,
         headers: headers(token)

    assert_response :success
    assert_equal 5, bundle.reload.passes_remaining, "subscription-covered user must not spend a pass"
  end
end
