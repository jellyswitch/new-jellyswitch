require "test_helper"

# Web Keys page XHR endpoint (POST /api/doors/:id/unlock, session-authenticated).
# Historically this only required login — any signed-in user could unlock any
# building door from a browser. It now enforces the same
# `user_can_access_building?` gate as the mobile unlock
# (Api::V1::DoorsController#unlock) and the same bundle burn-on-entry
# (Billing::DayPassBundles::ConsumeOnEntry), so web and app entrances follow
# one access + billing policy.
class Api::DoorsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @operator   = operators(:cowork_tahoe)
    @location   = locations(:cowork_tahoe_location)
    @member     = users(:cowork_tahoe_member)      # active subscription
    @non_member = users(:cowork_tahoe_non_member)  # no coverage at all
    @admin      = users(:cowork_tahoe_admin)       # staff (location management)
    @door       = Door.create!(
      name:      "Cowork Tahoe Front",
      slug:      "ct-front-#{SecureRandom.hex(4)}",
      location:  @location,
      operator:  @operator,
      kisi_id:   99002,
      available: true,
    )

    @kisi_url = "https://api.kisi.io/locks/#{@door.kisi_id}/unlock"
    stub_request(:post, @kisi_url).to_return(
      status:  200,
      body:    { success: true, lock_id: @door.kisi_id }.to_json,
      headers: { "Content-Type" => "application/json" },
    )

    host! "#{@operator.subdomain}.example.com"
  end

  def unlock!
    post "/api/doors/#{@door.id}/unlock", env: default_env
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

  # ---------------------------------------------------------------------------
  # Access gate
  # ---------------------------------------------------------------------------

  test "member with an active subscription unlocks a building door" do
    log_in @member

    assert_difference -> { DoorPunch.where(user: @member, door: @door).count }, 1 do
      unlock!
    end

    assert_response :success
    assert_equal true, JSON.parse(response.body)["success"]
    assert_requested :post, @kisi_url, times: 1
  end

  test "logged-in user with no coverage is denied" do
    log_in @non_member

    assert_no_difference -> { DoorPunch.count } do
      unlock!
    end

    assert_response :forbidden
    assert_equal false, JSON.parse(response.body)["success"]
    assert_not_requested :post, @kisi_url
  end

  test "staff unlocks regardless of personal coverage" do
    log_in @admin

    unlock!

    assert_response :success
    assert_requested :post, @kisi_url, times: 1
  end

  test "logged-out request is unauthorized" do
    unlock!

    assert_response :unauthorized
    assert_not_requested :post, @kisi_url
  end

  # ---------------------------------------------------------------------------
  # Bundle burn-on-entry parity with Api::V1::DoorUnlocking#perform_unlock
  # ---------------------------------------------------------------------------

  test "bundle-only member web unlock burns exactly one pass" do
    bundle = create_active_bundle(@non_member)
    log_in @non_member

    unlock!

    assert_response :success
    assert_equal 4, bundle.reload.passes_remaining
    assert_equal 1, DayPass.where(user: @non_member, location: @location, day: Date.current).count
    assert_requested :post, @kisi_url, times: 1
  end

  test "bundle-only member unlocking twice the same day burns only one pass" do
    bundle = create_active_bundle(@non_member)
    log_in @non_member

    unlock!
    assert_response :success
    unlock!
    assert_response :success

    assert_equal 4, bundle.reload.passes_remaining, "second entry same day must not burn again"
  end

  test "subscription member unlock does NOT burn a bundle pass" do
    bundle = create_active_bundle(@member)
    log_in @member

    unlock!

    assert_response :success
    assert_equal 5, bundle.reload.passes_remaining, "subscription-covered user must not spend a pass"
  end

  # ---------------------------------------------------------------------------
  # Private (admin-only) doors — Untethered "Pipkin Suite" regression: the Keys
  # list showed private doors to members, and unlock only checked building
  # access, so a lease-holder from another org opened a private door.
  # ---------------------------------------------------------------------------

  def private_door!(kisi: 99777)
    d = Door.create!(
      name: "Pipkin Suite", slug: "pipkin-#{SecureRandom.hex(4)}",
      location: @location, operator: @operator, kisi_id: kisi,
      available: true, private: true,
    )
    stub_request(:post, "https://api.kisi.io/locks/#{kisi}/unlock").to_return(
      status: 200, body: { success: true }.to_json, headers: { "Content-Type" => "application/json" },
    )
    d
  end

  test "Keys list hides a private door from a member" do
    door = private_door!
    log_in @member
    get "/api/doors", env: default_env

    assert_response :success
    ids = JSON.parse(response.body).map { |d| d["id"] }
    refute_includes ids, door.id, "member must not see a private door"
    assert_includes ids, @door.id, "public door is still listed"
  end

  test "a member with building access is DENIED a private door" do
    door = private_door!
    log_in @member
    post "/api/doors/#{door.id}/unlock", env: default_env

    assert_response :forbidden
    assert_match(/restricted/i, JSON.parse(response.body)["message"])
    assert_not_requested :post, "https://api.kisi.io/locks/#{door.kisi_id}/unlock"
  end

  test "staff can open a private door" do
    door = private_door!
    log_in @admin
    post "/api/doors/#{door.id}/unlock", env: default_env

    assert_response :success
    assert_requested :post, "https://api.kisi.io/locks/#{door.kisi_id}/unlock", times: 1
  end
end
