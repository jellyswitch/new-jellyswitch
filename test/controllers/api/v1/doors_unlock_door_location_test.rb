require "test_helper"

# The unlock endpoint's :id is client-supplied, so the access gate must run
# at the DOOR's location, not the requester's home location. Before this fix
# a member with home-location access at a multi-location operator could forge
# POST /api/v1/doors/:id/unlock with ANOTHER location's door id and Kisi
# would open it — the gate checked their home building. The approach path
# (AutoUnlocksController, beacon.location) and the web path
# (Api::DoorsController, @door.location) already gated on the door's own
# building; the v1 manual path was the one divergence (2026-08-07). The
# bundle burn-on-entry is likewise keyed to the building actually entered.
#
# The grants here are day-pass BUNDLES because the bundle clause is strictly
# location-scoped, which isolates WHERE the gate runs. Membership roaming
# (an all_hours plan opens any of its operator's buildings) is plan-level
# behavior shared with the approach path and is out of scope here.
class Api::V1::DoorsUnlockDoorLocationTest < ActionDispatch::IntegrationTest
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
      @other_location = create(:location, operator: @operator, name: "Fulton Annex",
                               time_zone: "Pacific Time (US & Canada)",
                               working_day_start: "06:00", working_day_end: "20:00")
      @guest = create(:user, operator: @operator, original_location: @location, current_location: @location)
      @home_type  = create(:day_pass_type, operator: @operator, location: @location)
      @other_type = create(:day_pass_type, operator: @operator, location: @other_location)
    end
    @home_door   = build_door(location: @location,       name: "Home Front Door",   kisi_id: 99081)
    @remote_door = build_door(location: @other_location, name: "Remote Front Door", kisi_id: 99082)
    @home_kisi_url   = kisi_url(@home_door)
    @remote_kisi_url = kisi_url(@remote_door)
    [@home_kisi_url, @remote_kisi_url].each do |url|
      stub_request(:post, url).to_return(
        status: 200, body: { success: true }.to_json,
        headers: { "Content-Type" => "application/json" },
      )
    end
  end

  def build_door(location:, name:, kisi_id:)
    Door.create!(
      name: name, slug: "#{name.parameterize}-#{SecureRandom.hex(4)}",
      location: location, operator: @operator, kisi_id: kisi_id, available: true,
    )
  end

  def kisi_url(door)
    "https://api.kisi.io/locks/#{door.kisi_id}/unlock"
  end

  def headers(user)
    token = JWT.encode(
      { user_id: user.id, operator_id: @operator.id, exp: 30.days.from_now.to_i },
      Rails.application.secret_key_base, "HS256",
    )
    { "Authorization" => "Bearer #{token}", "X-Operator-Subdomain" => @operator.subdomain,
      "Content-Type" => "application/json" }
  end

  def grant_bundle(location:, type:)
    ActsAsTenant.with_tenant(@operator) do
      create(:day_pass_bundle, user: @guest, billable: @guest, operator: @operator,
             location: location, day_pass_type: type)
    end
  end

  test "home-location access does not open another location's door" do
    grant_bundle(location: @location, type: @home_type)
    travel_to @zone.parse("#{@tuesday} 10:00") do
      assert_no_difference -> { DoorPunch.count } do
        post "/api/v1/doors/#{@remote_door.id}/unlock", headers: headers(@guest)
      end
      assert_response :forbidden
      assert_not_requested :post, @remote_kisi_url
    end
  end

  test "the same access still opens the member's own door" do
    grant_bundle(location: @location, type: @home_type)
    travel_to @zone.parse("#{@tuesday} 10:00") do
      post "/api/v1/doors/#{@home_door.id}/unlock", headers: headers(@guest)
      assert_response :success
      assert_requested :post, @home_kisi_url, times: 1
    end
  end

  test "access at the door's location admits and burns at that location" do
    # Mirrors the approach path: a bundle for the door's building admits its
    # holder there even though their home location is elsewhere, and the
    # burn (minted pass + decrement) books against the building entered.
    bundle = grant_bundle(location: @other_location, type: @other_type)
    travel_to @zone.parse("#{@tuesday} 10:00") do
      post "/api/v1/doors/#{@remote_door.id}/unlock", headers: headers(@guest)
      assert_response :success
      assert_requested :post, @remote_kisi_url, times: 1
    end
    assert_equal 4, bundle.reload.passes_remaining
    assert_equal @other_location, @guest.day_passes.reload.last.location
  end
end
