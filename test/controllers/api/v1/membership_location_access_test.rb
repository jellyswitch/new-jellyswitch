require "test_helper"

# End-to-end proof at the door: a membership admits its holder at the plan's
# OWN building and no longer roams across a multi-location operator. Exercised
# through the beacon approach path because its gate already runs at the door's
# real building (beacon.location) — this is the request a member physically
# standing at the wrong building produces. The same predicate serves the
# manual and web unlock paths.
class Api::V1::MembershipLocationAccessTest < ActionDispatch::IntegrationTest
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
      @member = create(:user, operator: @operator, original_location: @location, current_location: @location)
      @plan = create(:plan, operator: @operator, location: @location,
                     building_access_level: :all_hours)
      create(:subscription, plan: @plan, subscribable: @member, billable: @member)
    end
    @home_beacon   = build_beacon(location: @location,       kisi_id: 99083, minor: 1)
    @remote_beacon = build_beacon(location: @other_location, kisi_id: 99084, minor: 2)
    Rails.cache.clear
  end

  def build_beacon(location:, kisi_id:, minor:)
    door = Door.create!(
      name: "#{location.name} Front Door", slug: "#{location.name.parameterize}-door-#{SecureRandom.hex(4)}",
      location: location, operator: @operator, kisi_id: kisi_id, available: true,
    )
    Beacon.create!(
      name: "#{location.name} Beacon", uuid: SecureRandom.uuid, major: 100, minor: minor,
      operator: @operator, location: location, door: door, available: true,
    )
  end

  def headers(user)
    token = JWT.encode(
      { user_id: user.id, operator_id: @operator.id, exp: 30.days.from_now.to_i },
      Rails.application.secret_key_base, "HS256",
    )
    { "Authorization" => "Bearer #{token}", "X-Operator-Subdomain" => @operator.subdomain,
      "Content-Type" => "application/json" }
  end

  def approach(beacon)
    post "/api/v1/door/auto_unlock",
         params: { uuid: beacon.uuid, major: beacon.major, minor: beacon.minor,
                   nonce: SecureRandom.hex(16) }.to_json,
         headers: headers(@member)
  end

  test "the membership admits its holder at the plan's own building" do
    travel_to @zone.parse("#{@tuesday} 10:00") do
      approach(@home_beacon)
      assert_response :success
    end
  end

  test "the membership does not open another building of the operator" do
    travel_to @zone.parse("#{@tuesday} 10:00") do
      assert_no_difference -> { DoorPunch.count } do
        approach(@remote_beacon)
      end
      assert_response :forbidden
    end
  end

  test "a plan with no location keeps operator-wide access" do
    ActsAsTenant.with_tenant(@operator) { @plan.update!(location: nil) }
    travel_to @zone.parse("#{@tuesday} 10:00") do
      approach(@remote_beacon)
      assert_response :success
    end
  end
end
