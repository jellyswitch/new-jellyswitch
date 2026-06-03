require "test_helper"

# Hardening for the phantom location 1627 ("Cowork Tahoe ", visible=false under
# the Untethered operator): PATCH /api/v1/me/location took a raw location_id and
# would happily switch a member onto a hidden/orphan space. A member may now
# only switch to a *visible* location; admins/superadmins may still target a
# hidden one (e.g. a deprecated or staff-only space). Pairs with the
# /api/v1/me serializer fix (see users_me_visibility_test.rb).
class Api::V1::UsersSwitchLocationTest < ActionDispatch::IntegrationTest
  setup do
    @member   = users(:cowork_tahoe_member)
    @admin    = users(:cowork_tahoe_admin)
    @operator = @member.operator
    @visible  = locations(:cowork_tahoe_location)
    @hidden   = Location.create!(
      name:              "Hidden Switch Space",
      operator:          @operator,
      visible:           false,
      time_zone:         "Pacific Time (US & Canada)",
      working_day_start: "09:00",
      working_day_end:   "18:00",
    )
  end

  def token_for(user)
    JWT.encode(
      { user_id: user.id, operator_id: @operator.id, exp: 30.days.from_now.to_i },
      Rails.application.secret_key_base,
      "HS256",
    )
  end

  def switch(user, location_id)
    patch "/api/v1/me/location",
      params: { location_id: location_id },
      headers: { "Authorization" => "Bearer #{token_for(user)}", "X-Operator-Subdomain" => @operator.subdomain }
  end

  test "member cannot switch to a hidden location" do
    switch(@member, @hidden.id)
    assert_response :not_found
    assert_not_equal @hidden.id, @member.reload.current_location_id
  end

  test "member can switch to a visible location" do
    switch(@member, @visible.id)
    assert_response :success
    assert_equal @visible.id, @member.reload.current_location_id
  end

  test "admin can switch to a hidden location" do
    switch(@admin, @hidden.id)
    assert_response :success
    assert_equal @hidden.id, @admin.reload.current_location_id
  end
end
