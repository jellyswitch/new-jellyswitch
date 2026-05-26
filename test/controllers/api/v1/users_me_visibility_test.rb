require "test_helper"

# Regression coverage for the location-visibility leak that exposed phantom
# location 1627 ("Cowork Tahoe ", visible=false) to the React Native
# LocationSwitchScreen via GET /api/v1/me. The screen reads
# `response.data.locations` directly, so any hidden location in the JSON
# becomes a tappable option in the location-switcher UI.
#
# These tests intentionally hit the API endpoint end-to-end (no controller
# stubbing) so the assertion catches both controller-level filter mistakes
# and any future serializer regressions.
class Api::V1::UsersMeVisibilityTest < ActionDispatch::IntegrationTest
  setup do
    @user      = users(:cowork_tahoe_admin)
    @operator  = @user.operator
    @visible   = locations(:cowork_tahoe_location)
    @hidden    = Location.create!(
      name:               "Hidden Test Location",
      operator:           @operator,
      visible:            false,
      time_zone:          "Pacific Time (US & Canada)",
      working_day_start:  "09:00",
      working_day_end:    "18:00",
    )
    @token = JWT.encode(
      { user_id: @user.id, operator_id: @operator.id, exp: 30.days.from_now.to_i },
      Rails.application.secret_key_base,
      "HS256",
    )
  end

  test "GET /api/v1/me excludes hidden locations from the locations array" do
    get "/api/v1/me",
        headers: { "Authorization" => "Bearer #{@token}", "X-Operator-Subdomain" => @operator.subdomain }

    assert_response :success
    body = JSON.parse(response.body)
    location_ids = body.fetch("locations").map { |l| l["id"] }

    assert_includes location_ids, @visible.id,
      "expected visible location #{@visible.id} in /api/v1/me response"
    refute_includes location_ids, @hidden.id,
      "hidden location #{@hidden.id} leaked into /api/v1/me — this is the LocationSwitchScreen phantom-space bug"
  end
end
