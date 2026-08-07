require "test_helper"

# A day pass covers the LOCATION it was bought for. At a multi-location
# operator (Untethered: Lake Tahoe NV / Fulton MO / …) the unlock gate's
# day-pass clause was unscoped, so a pass bought for one location listed keys
# and opened doors at every other location (2026-08-07). The clause now uses
# the lenient HasLocation.for_location scope: passes stamped with another
# location are rejected, while legacy location-less passes keep working
# everywhere. Membership, lease, bundle (already location-scoped), and
# reservation access are unchanged.
class Api::V1::DoorsLocationScopeTest < ActionDispatch::IntegrationTest
  include ActiveSupport::Testing::TimeHelpers

  setup do
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
    @zone = ActiveSupport::TimeZone["Pacific Time (US & Canada)"]
    # Pin the test date BEFORE any travel_to — a dynamic helper would
    # recompute relative to the frozen clock and drift by a week.
    @tuesday = Date.current.next_occurring(:tuesday) + 7
    ActsAsTenant.with_tenant(@operator) do
      @location.update!(time_zone: "Pacific Time (US & Canada)",
                        working_day_start: "06:00", working_day_end: "20:00")
      @other_location = create(:location, operator: @operator, name: "Fulton Annex")
      @guest = create(:user, operator: @operator, original_location: @location, current_location: @location)
      @type = create(:day_pass_type, operator: @operator, location: @location,
                     amount_in_cents: 4000, always_allow_building_access: false)
      @other_type = create(:day_pass_type, operator: @operator, location: @other_location,
                           amount_in_cents: 4000, always_allow_building_access: false)
      @other_allday_type = create(:day_pass_type, operator: @operator, location: @other_location,
                                  amount_in_cents: 4000, always_allow_building_access: true)
    end
    @door = Door.create!(
      name: "Location Scope Door", slug: "loc-scope-door-#{SecureRandom.hex(4)}",
      location: @location, operator: @operator, kisi_id: 99078, available: true,
    )
    @kisi_url = "https://api.kisi.io/locks/#{@door.kisi_id}/unlock"
    stub_request(:post, @kisi_url).to_return(
      status: 200,
      body: { success: true, lock_id: @door.kisi_id }.to_json,
      headers: { "Content-Type" => "application/json" },
    )
    Rails.cache.clear
  end

  def headers(user)
    token = JWT.encode(
      { user_id: user.id, operator_id: @operator.id, exp: 30.days.from_now.to_i },
      Rails.application.secret_key_base, "HS256",
    )
    { "Authorization" => "Bearer #{token}", "X-Operator-Subdomain" => @operator.subdomain,
      "Content-Type" => "application/json" }
  end

  def grant_pass(location:, type:)
    ActsAsTenant.with_tenant(@operator) do
      create(:day_pass, user: @guest, billable: @guest, operator: @operator,
             location: location, day_pass_type: type, day: @tuesday)
    end
  end

  def listed_door_ids(user)
    get "/api/v1/doors", headers: headers(user)
    assert_response :success
    JSON.parse(response.body).map { |d| d["id"] }
  end

  test "a pass bought for another location neither lists keys nor opens the door here" do
    grant_pass(location: @other_location, type: @other_type)
    travel_to @zone.parse("#{@tuesday} 10:00") do
      assert_equal [], listed_door_ids(@guest)
      post "/api/v1/doors/#{@door.id}/unlock", headers: headers(@guest)
      assert_response :forbidden
      assert_not_requested :post, @kisi_url
    end
  end

  test "a pass for this location still lists keys and opens the door" do
    grant_pass(location: @location, type: @type)
    travel_to @zone.parse("#{@tuesday} 10:00") do
      assert_includes listed_door_ids(@guest), @door.id
      post "/api/v1/doors/#{@door.id}/unlock", headers: headers(@guest)
      assert_response :success
      assert_requested :post, @kisi_url, times: 1
    end
  end

  test "a legacy pass with no location still opens the door (lenient scope)" do
    grant_pass(location: nil, type: @type)
    travel_to @zone.parse("#{@tuesday} 10:00") do
      assert_includes listed_door_ids(@guest), @door.id
      post "/api/v1/doors/#{@door.id}/unlock", headers: headers(@guest)
      assert_response :success
    end
  end

  test "an always-allow pass type from another location does not open this door at 2 AM" do
    grant_pass(location: @other_location, type: @other_allday_type)
    travel_to @zone.parse("#{@tuesday} 02:00") do
      post "/api/v1/doors/#{@door.id}/unlock", headers: headers(@guest)
      assert_response :forbidden
    end
  end

  test "approach auto-unlock rejects a pass bought for another location" do
    # The BLE path gates on beacon.location (the door's building) — this is
    # the request a member physically standing at the wrong location produces.
    beacon = beacons(:cowork_tahoe_front_door_beacon)
    beacon.update!(door: @door)
    grant_pass(location: @other_location, type: @other_type)
    travel_to @zone.parse("#{@tuesday} 10:00") do
      assert_no_difference -> { DoorPunch.count } do
        post "/api/v1/door/auto_unlock",
             params: { uuid: beacon.uuid, major: beacon.major, minor: beacon.minor,
                       nonce: SecureRandom.hex(16) }.to_json,
             headers: headers(@guest)
      end
      assert_response :forbidden
    end
  end

  test "approach auto-unlock still admits a pass for this location" do
    beacon = beacons(:cowork_tahoe_front_door_beacon)
    beacon.update!(door: @door)
    grant_pass(location: @location, type: @type)
    travel_to @zone.parse("#{@tuesday} 10:00") do
      post "/api/v1/door/auto_unlock",
           params: { uuid: beacon.uuid, major: beacon.major, minor: beacon.minor,
                     nonce: SecureRandom.hex(16) }.to_json,
           headers: headers(@guest)
      assert_response :success
    end
  end
end
