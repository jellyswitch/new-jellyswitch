require "test_helper"

# A reservation admits its holder to the building the booked ROOM is in —
# the ±window clause (ADR 0013) previously ignored the gate location, so a
# booking at one building of a multi-location operator opened every other
# building's doors during its window. Exercised through the beacon approach
# path because its gate already runs at the door's real building
# (beacon.location); the same predicate serves the manual and web paths.
class Api::V1::ReservationLocationAccessTest < ActionDispatch::IntegrationTest
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
      # No membership, pass, bundle, or lease — the reservation is the only
      # thing that can admit this visitor.
      @guest = create(:user, operator: @operator, original_location: @location, current_location: @location)
      room = create(:room, operator: @operator, location: @location)
      create(:reservation, user: @guest, room: room,
             datetime_in: @zone.parse("#{@tuesday} 10:00"), minutes: 60)
    end
    @home_beacon   = build_beacon(location: @location,       kisi_id: 99085, minor: 3)
    @remote_beacon = build_beacon(location: @other_location, kisi_id: 99086, minor: 4)
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
         headers: headers(@guest)
  end

  test "an in-window reservation admits its holder at the booked room's building" do
    travel_to @zone.parse("#{@tuesday} 10:30") do
      approach(@home_beacon)
      assert_response :success
    end
  end

  test "the reservation does not open another building of the operator" do
    travel_to @zone.parse("#{@tuesday} 10:30") do
      assert_no_difference -> { DoorPunch.count } do
        approach(@remote_beacon)
      end
      assert_response :forbidden
    end
  end
end
