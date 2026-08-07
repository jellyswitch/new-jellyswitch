require "test_helper"

# Reserve Now starts a booking RIGHT NOW — so when the location is closed it
# must not offer bookable rooms to hour-bounded users (day-pass guests, new
# signups). Members and leaseholders book 24/7 and keep the normal payload.
# (Nash incident, 2026-08-07: without this, a 1:34 AM Reserve Now booking
# would re-open the door via the reservation ±window even after day-pass
# access itself was bounded to posted hours.)
class Api::V1::RoomsReserveNowHoursTest < ActionDispatch::IntegrationTest
  include ActiveSupport::Testing::TimeHelpers

  setup do
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
    @zone = ActiveSupport::TimeZone["Pacific Time (US & Canada)"]
    @tuesday = Date.current.next_occurring(:tuesday) + 7
    ActsAsTenant.with_tenant(@operator) do
      @location.update!(time_zone: "Pacific Time (US & Canada)",
                        working_day_start: "06:00", working_day_end: "20:00",
                        open_saturday: false, open_sunday: false)
      @room = create(:room, operator: @operator, location: @location,
                     hourly_rate_in_cents: 0, include_with_day_pass: true, visible: true)
      @guest = create(:user, operator: @operator, original_location: @location, current_location: @location)
      type = create(:day_pass_type, operator: @operator, location: @location, amount_in_cents: 4000)
      create(:day_pass, user: @guest, billable: @guest, operator: @operator,
             location: @location, day_pass_type: type, day: @tuesday)
    end
  end

  def headers(user)
    token = JWT.encode({ user_id: user.id, exp: 30.days.from_now.to_i },
                       Rails.application.secret_key_base, "HS256")
    { "Authorization" => "Bearer #{token}", "X-Operator-Subdomain" => @operator.subdomain,
      "Content-Type" => "application/json" }
  end

  test "closed location offers a guest no bookable rooms" do
    travel_to @zone.parse("#{@tuesday} 02:00") do
      get "/api/v1/reserve_now", headers: headers(@guest)
      assert_response :success
      body = JSON.parse(response.body)
      assert_equal true, body["closed"]
      assert body["rooms"].none? { |r| r["available"] }, "no room should be bookable while closed"
    end
  end

  test "open location keeps the normal payload for a guest" do
    travel_to @zone.parse("#{@tuesday} 10:00") do
      get "/api/v1/reserve_now", headers: headers(@guest)
      assert_response :success
      body = JSON.parse(response.body)
      assert_not_equal true, body["closed"]
      assert body["hero_room"].present?, "an open location offers bookable rooms"
    end
  end

  test "a subscribed member keeps bookable rooms while the location is closed" do
    plans(:cowork_tahoe_full_time_plan).update!(location_id: @location.id)
    travel_to @zone.parse("#{@tuesday} 02:00") do
      get "/api/v1/reserve_now", headers: headers(users(:cowork_tahoe_member))
      assert_response :success
      body = JSON.parse(response.body)
      assert_not_equal true, body["closed"]
      assert body["hero_room"].present?
    end
  end
end
