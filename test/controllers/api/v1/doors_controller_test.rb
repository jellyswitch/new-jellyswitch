require "test_helper"

# Coverage for the manual /api/v1/doors/:id/unlock action.
# Added when Api::V1::DoorUnlocking concern was extracted so we have a
# safety net for behavior parity with the pre-refactor inline code.
class Api::V1::DoorsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @member     = users(:cowork_tahoe_member)
    @non_member = users(:cowork_tahoe_non_member)
    @operator   = operators(:cowork_tahoe)
    @location   = locations(:cowork_tahoe_location)
    @door       = Door.create!(
      name:        "Cowork Tahoe Front",
      slug:        "ct-front-#{SecureRandom.hex(4)}",
      location:    @location,
      operator:    @operator,
      kisi_id:     99001,
      available:   true,
    )

    @kisi_url = "https://api.kisi.io/locks/#{@door.kisi_id}/unlock"
    stub_request(:post, @kisi_url).to_return(
      status:  200,
      body:    { success: true, lock_id: @door.kisi_id }.to_json,
      headers: { "Content-Type" => "application/json" },
    )
  end

  def headers(user)
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

  test "active member unlock logs manual DoorPunch" do
    assert_difference -> { DoorPunch.where(method: "manual").count }, 2 do
      post "/api/v1/doors/#{@door.id}/unlock", headers: headers(@member)
    end

    assert_response :success
    assert_equal true, JSON.parse(response.body)["success"]
    assert_requested :post, @kisi_url, times: 1
  end

  # Kisi-side failure (controller offline, fac001 — Zephyr Cove 2026-08-13 and
  # 2026-08-27): the unlock must NOT report success. Before the fix the
  # controller rescued exceptions only, and Kisi::Client returns (never raises)
  # on a non-2xx — so the member saw "Door unlocked" while the door stayed shut,
  # and the punch row said "unlocked" with the error buried in json.
  test "Kisi controller offline reports failure to the member and stamps the punch failed" do
    stub_request(:post, @kisi_url).to_return(
      status:  503,
      body:    { code: "fac001", error: "The Kisi controller is currently unavailable." }.to_json,
      headers: { "Content-Type" => "application/json" },
    )

    assert_difference -> { DoorPunch.where(method: "manual").count }, 2 do
      post "/api/v1/doors/#{@door.id}/unlock", headers: headers(@member)
    end

    assert_response :success # 200 + success:false is the shape every app surface alerts on
    body = JSON.parse(response.body)
    assert_equal false, body["success"]
    assert_match(/offline/i, body["message"])

    punch = DoorPunch.where(method: "manual").where.not(json: nil).order(:id).last
    assert_equal "failed", punch.status
    assert_equal "fac001", punch.json["code"]
  end

  test "successful unlock stamps the reconciled punch unlocked" do
    post "/api/v1/doors/#{@door.id}/unlock", headers: headers(@member)

    assert_response :success
    assert_equal "Door unlocked", JSON.parse(response.body)["message"]
    punch = DoorPunch.where(method: "manual").where.not(json: nil).order(:id).last
    assert_equal "unlocked", punch.status
  end

  test "non-member is denied" do
    post "/api/v1/doors/#{@door.id}/unlock", headers: headers(@non_member)
    assert_response :forbidden
    assert_not_requested :post, @kisi_url
  end

  # ADR 0013: a reservation grants access only inside its ±window, not all day.
  def reservation_room
    Room.create!(name: "RW-#{SecureRandom.hex(3)}", slug: "rw-#{SecureRandom.hex(4)}",
                 location: @location, operator: @operator, rentable: true)
  end

  test "a reservation inside the access window unlocks the door for an otherwise-denied user" do
    Reservation.new(user: @non_member, room: reservation_room,
                    datetime_in: 30.minutes.from_now, minutes: 60).save!(validate: false)

    post "/api/v1/doors/#{@door.id}/unlock", headers: headers(@non_member)

    assert_response :success
    assert_requested :post, @kisi_url, times: 1
  end

  test "a reservation outside the access window does NOT unlock the door (no all-day grant)" do
    Reservation.new(user: @non_member, room: reservation_room,
                    datetime_in: 3.days.from_now.change(hour: 12), minutes: 60).save!(validate: false)

    post "/api/v1/doors/#{@door.id}/unlock", headers: headers(@non_member)

    assert_response :forbidden
    assert_not_requested :post, @kisi_url
  end

  # ---------------------------------------------------------------------------
  # Bundle-pass consumption tests — manual unlock path
  # ---------------------------------------------------------------------------

  # Build a bundle-only user: no subscription, no day pass, no lease,
  # no reservation — only an active DayPassBundle with passes.
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

  test "bundle-only user unlocking the door burns exactly one pass" do
    # Bundle door access is bounded to posted hours (ADR 0023) — freeze to a
    # mid-morning on today's date so this test isn't hostage to the wall
    # clock (fixture location: Pacific, 06:00–20:00; hours coverage lives in
    # doors_hours_test).
    travel_to Time.zone.parse("#{Date.current} 10:00") do
      user   = bundle_user
      bundle = create_active_bundle(user)

      post "/api/v1/doors/#{@door.id}/unlock", headers: headers(user)

      assert_response :success
      assert_equal passes_before = 5, bundle.passes_remaining   # sanity
      assert_equal 4, bundle.reload.passes_remaining
      assert_equal 1, DayPass.where(user: user, location: @location, day: Date.current).count
    end
  end

  test "bundle-only user unlocking twice the same day burns only one pass total (idempotent)" do
    travel_to Time.zone.parse("#{Date.current} 10:00") do # posted-hours bound, see above
      user   = bundle_user
      bundle = create_active_bundle(user)

      post "/api/v1/doors/#{@door.id}/unlock", headers: headers(user)
      assert_response :success

      post "/api/v1/doors/#{@door.id}/unlock", headers: headers(user)
      assert_response :success

      assert_equal 4, bundle.reload.passes_remaining, "second unlock must not burn another pass"
    end
  end

  test "member (active subscription) unlocking does NOT burn a bundle pass" do
    user   = users(:cowork_tahoe_member)   # has cowork_tahoe_subscription fixture
    bundle = create_active_bundle(user)

    post "/api/v1/doors/#{@door.id}/unlock", headers: headers(user)

    assert_response :success
    assert_equal 5, bundle.reload.passes_remaining, "subscription-covered user must not spend a pass"
  end

  test "door list shows public doors (incl. unflagged) and hides private ones" do
    # @door has the default private=false — the case that used to be NULL and
    # got silently dropped from the member list by `where(private: false)`.
    public_door  = @door
    private_door = Door.create!(
      name: "Server Room", slug: "srv-#{SecureRandom.hex(4)}",
      location: @location, operator: @operator, kisi_id: 99099,
      available: true, private: true,
    )

    get "/api/v1/doors", headers: headers(@member)
    assert_response :success
    ids = JSON.parse(response.body).map { |d| d["id"] }

    assert_includes ids, public_door.id, "member should see the public door"
    refute_includes ids, private_door.id, "member should not see the private door"
  end

  # The Keys list must gate on the SAME predicate as unlock — a reservation
  # inside its ±window (ADR 0013) has to surface door rows, or the visitor
  # has a valid unlock right and no button to exercise it (Chris Horne,
  # 2026-07-21: paid 8am booking, empty Keys tab, stranded at the door).
  test "Keys list shows doors for a reservation-only visitor inside the access window" do
    Reservation.new(user: @non_member, room: reservation_room,
                    datetime_in: 30.minutes.from_now, minutes: 60).save!(validate: false)

    get "/api/v1/doors", headers: headers(@non_member)

    assert_response :success
    ids = JSON.parse(response.body).map { |d| d["id"] }
    assert_includes ids, @door.id, "visitor inside their reservation window should see the door"
  end

  test "Keys list stays empty for a reservation-only visitor outside the access window" do
    Reservation.new(user: @non_member, room: reservation_room,
                    datetime_in: 3.days.from_now.change(hour: 12), minutes: 60).save!(validate: false)

    get "/api/v1/doors", headers: headers(@non_member)

    assert_response :success
    assert_equal [], JSON.parse(response.body), "no reservation window open — no keys"
  end

  test "a member with building access is DENIED unlocking a private door" do
    private_door = Door.create!(
      name: "Server Room", slug: "srv-#{SecureRandom.hex(4)}",
      location: @location, operator: @operator, kisi_id: 99098,
      available: true, private: true,
    )
    kisi = "https://api.kisi.io/locks/#{private_door.kisi_id}/unlock"
    stub_request(:post, kisi).to_return(
      status: 200, body: { success: true }.to_json, headers: { "Content-Type" => "application/json" },
    )

    post "/api/v1/doors/#{private_door.id}/unlock", headers: headers(@member)

    assert_response :forbidden
    assert_match(/restricted/i, JSON.parse(response.body)["message"])
    assert_not_requested :post, kisi
  end
end
