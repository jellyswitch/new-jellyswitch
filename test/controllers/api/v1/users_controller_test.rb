require "test_helper"

# End-to-end coverage for /api/v1/me + related self-service endpoints.
# The hidden-location-leak in PR #437 lived in /me; the location-visibility
# regression guard already lives in users_me_visibility_test.rb. These tests
# cover the rest of the surface: auth gating, strong-params enforcement on
# update, password change rules, push-token registration, terms acceptance,
# location switching, and email-preference toggling.
class Api::V1::UsersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @operator = operators(:cowork_tahoe)
    @user     = users(:cowork_tahoe_member)
    @password = "correct-horse-battery-staple"
    @user.update!(password: @password)
    @token    = JWT.encode(
      { user_id: @user.id, operator_id: @operator.id, exp: 30.days.from_now.to_i },
      Rails.application.secret_key_base,
      "HS256",
    )
    @auth = { "Authorization" => "Bearer #{@token}", "X-Operator-Subdomain" => @operator.subdomain }
  end

  # ---------- GET /api/v1/me ----------

  test "me without a token returns 401" do
    get "/api/v1/me"
    assert_response :unauthorized
  end

  test "me with an invalid token returns 401" do
    get "/api/v1/me", headers: { "Authorization" => "Bearer not-a-real-jwt" }
    assert_response :unauthorized
  end

  test "me returns the authenticated user's profile" do
    get "/api/v1/me", headers: @auth

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal @user.id, body["id"]
    assert_equal @user.email, body["email"]
    assert_equal @operator.name, body["operator"]
    assert_equal @operator.subdomain, body["operator_subdomain"]
    assert body.key?("features")
    assert body.key?("locations")
    assert body.key?("has_active_coverage")
  end

  # ---------- PATCH /api/v1/me ----------

  test "update changes whitelisted profile fields" do
    patch "/api/v1/me",
          params:  { user: { name: "Renamed Member", bio: "Hello world" } },
          headers: @auth

    assert_response :success
    assert_equal true, JSON.parse(response.body)["success"]
    @user.reload
    assert_equal "Renamed Member", @user.name
    assert_equal "Hello world",    @user.bio
  end

  test "update ignores non-permitted attributes (no mass assignment)" do
    original_role = @user.role
    original_email = @user.email

    patch "/api/v1/me",
          params:  { user: { name: "Still Me", role: "superadmin", admin: true, superadmin: true, email: "evil@example.com" } },
          headers: @auth

    assert_response :success
    @user.reload
    assert_equal "Still Me",      @user.name
    assert_equal original_role,   @user.role,       "role must not be settable via /api/v1/me"
    assert_equal false,           @user.admin?,     "admin must not be settable via /api/v1/me"
    assert_equal false,           @user.superadmin?, "superadmin must not be settable via /api/v1/me"
    assert_equal original_email,  @user.email,      "email must not be settable via /api/v1/me"
  end

  test "update returns 422 when validation fails" do
    patch "/api/v1/me",
          params:  { user: { name: "" } },
          headers: @auth

    assert_response :unprocessable_entity
    assert JSON.parse(response.body)["error"].present?
  end

  # ---------- PATCH /api/v1/me/password ----------

  test "change_password with wrong current password returns 422" do
    patch "/api/v1/me/password",
          params:  { current_password: "wrong", new_password: "newpassword" },
          headers: @auth

    assert_response :unprocessable_entity
    assert_match(/current password/i, JSON.parse(response.body)["error"])
  end

  test "change_password with too-short new password returns 422" do
    patch "/api/v1/me/password",
          params:  { current_password: @password, new_password: "abc" },
          headers: @auth

    assert_response :unprocessable_entity
  end

  test "change_password with valid input updates the password digest" do
    original_digest = @user.password_digest

    patch "/api/v1/me/password",
          params:  { current_password: @password, new_password: "newpassword123" },
          headers: @auth

    assert_response :success
    @user.reload
    refute_equal original_digest, @user.password_digest
    assert @user.authenticate("newpassword123"),
      "user should be able to authenticate with the new password"
  end

  # ---------- POST /api/v1/me/push_token ----------

  test "register_push_token stores ios token on the user" do
    post "/api/v1/me/push_token",
         params:  { platform: "ios", token: "ios-device-token-abc" },
         headers: @auth

    assert_response :success
    assert_equal "ios-device-token-abc", @user.reload.ios_token
  end

  test "register_push_token stores android token on the user" do
    post "/api/v1/me/push_token",
         params:  { platform: "android", token: "android-device-token-xyz" },
         headers: @auth

    assert_response :success
    assert_equal "android-device-token-xyz", @user.reload.android_token
  end

  test "register_push_token with unknown platform is a no-op but returns success" do
    original_ios     = @user.ios_token
    original_android = @user.android_token

    post "/api/v1/me/push_token",
         params:  { platform: "windows-phone", token: "irrelevant" },
         headers: @auth

    assert_response :success
    @user.reload
    assert_equal original_ios,     @user.ios_token
    assert_equal original_android, @user.android_token
  end

  test "register_push_token without auth returns 401" do
    post "/api/v1/me/push_token", params: { platform: "ios", token: "x" }
    assert_response :unauthorized
  end

  # ---------- POST /api/v1/me/accept_terms ----------

  test "accept_terms stamps terms_accepted_at" do
    @user.update_column(:terms_accepted_at, nil)

    post "/api/v1/me/accept_terms", headers: @auth

    assert_response :success
    assert @user.reload.terms_accepted_at.present?
  end

  # ---------- PATCH /api/v1/me/location ----------

  test "switch_location moves current_location within the same operator" do
    other = Location.create!(
      name:              "Second Location",
      operator:          @operator,
      visible:           true,
      time_zone:         "Pacific Time (US & Canada)",
      working_day_start: "09:00",
      working_day_end:   "18:00",
    )

    patch "/api/v1/me/location",
          params:  { location_id: other.id },
          headers: @auth

    assert_response :success
    assert_equal other.id, @user.reload.current_location_id
  end

  test "switch_location with unknown id returns 404" do
    patch "/api/v1/me/location",
          params:  { location_id: 0 },
          headers: @auth

    assert_response :not_found
  end

  # ---------- PATCH /api/v1/me/email_preferences ----------

  test "update_email_preferences flips marketing_consent on" do
    @user.update!(marketing_consent: false)

    patch "/api/v1/me/email_preferences",
          params:  { marketing_opt_in: "true" },
          headers: @auth

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal true, body["marketing_opt_in"]
    assert_equal true, @user.reload.marketing_consent
  end

  test "update_email_preferences flips marketing_consent off" do
    @user.update!(marketing_consent: true)

    patch "/api/v1/me/email_preferences",
          params:  { marketing_opt_in: "false" },
          headers: @auth

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal false, body["marketing_opt_in"]
    assert_equal false, @user.reload.marketing_consent
  end
end
