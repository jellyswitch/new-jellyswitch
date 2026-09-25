require "test_helper"

# The app's Change Location screen (PATCH /api/v1/me/location) writes
# current_location, but Api::V1::BaseController#current_location used to read
# original_location FIRST — so the switch "succeeded" while announcements,
# plans, doors, etc. stayed at the signup location (Untethered Fulton members
# signed up at Lake Tahoe could never move, 2026-09-24). The API now uses
# User#active_location: the switch wins, signup location is the fallback, and a
# location of another operator is ignored.
class Api::V1::LocationSwitchTest < ActionDispatch::IntegrationTest
  setup do
    @operator = operators(:cowork_tahoe)
    @home     = locations(:cowork_tahoe_location)
    ActsAsTenant.with_tenant(@operator) do
      @other  = create(:location, operator: @operator, name: "Fulton Annex")
      @member = create(:user, operator: @operator, original_location: @home, current_location: @home)
      Announcement.create!(operator: @operator, location: @home,  user: @member, body: "Home news")
      Announcement.create!(operator: @operator, location: @other, user: @member, body: "Fulton news")
    end
  end

  def headers
    token = JWT.encode(
      { user_id: @member.id, operator_id: @operator.id, exp: 30.days.from_now.to_i },
      Rails.application.secret_key_base, "HS256",
    )
    { "Authorization" => "Bearer #{token}", "X-Operator-Subdomain" => @operator.subdomain,
      "Content-Type" => "application/json" }
  end

  def announcement_bodies
    get "/api/v1/announcements", headers: headers
    assert_response :success
    JSON.parse(response.body).map { |a| a["body"] }
  end

  test "switching location moves location-scoped API data and /me to the new location" do
    assert_equal ["Home news"], announcement_bodies

    patch "/api/v1/me/location", params: { location_id: @other.id }.to_json, headers: headers
    assert_response :success

    assert_equal ["Fulton news"], announcement_bodies
    get "/api/v1/me", headers: headers
    me = JSON.parse(response.body)
    assert_equal @other.id, me["location_id"]
    assert_equal "Fulton Annex", me["location"]
  end

  test "falls back to the signup location when no switch was made" do
    @member.update_columns(current_location_id: nil)
    assert_equal ["Home news"], announcement_bodies
  end

  test "ignores a current_location belonging to another operator" do
    foreign = create(:location, operator: create(:operator, subdomain: "rival-loc"), name: "Rival")
    @member.update_columns(current_location_id: foreign.id)
    assert_equal ["Home news"], announcement_bodies
    assert_equal @home, @member.reload.active_location
  end
end

# Staff switching to a location outside their admin boundary keep a working
# admin app at their home location instead of a blanket 403.
class Api::V1::AdminLocationSwitchTest < ActionDispatch::IntegrationTest
  setup do
    @operator = operators(:cowork_tahoe)
    @home     = locations(:cowork_tahoe_location)
    @manager  = users(:cowork_tahoe_community_manager) # manages only @home
    ActsAsTenant.with_tenant(@operator) do
      @other = create(:location, operator: @operator, name: "Unmanaged Annex")
    end
    @manager.update_columns(original_location_id: @home.id, current_location_id: @other.id)
  end

  test "admin API stays usable after switching to an unmanaged location" do
    token = JWT.encode({ user_id: @manager.id, exp: 30.days.from_now.to_i },
                       Rails.application.secret_key_base, "HS256")
    get "/api/v1/admin/announcements",
        headers: { "Authorization" => "Bearer #{token}", "X-Operator-Subdomain" => @operator.subdomain }
    assert_response :success
  end
end
