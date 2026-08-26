require "test_helper"

# Regression: Untethered (our one live multi-location operator) could not
# recover accounts at all. Operator::BaseController#reset_location redirects a
# logged-out visitor to the landing page whenever current_location is blank,
# and SessionsHelper only auto-resolves a location when the operator has
# exactly one. So both the "forgot password" form and the emailed
# /password_resets/:token/edit link bounced to "/", discarding the token.
class Operator::PasswordResetsReachabilityTest < ActionDispatch::IntegrationTest
  setup do
    setup_initial_user_fixtures
    @operator = operators(:cowork_tahoe)
    @user = users(:cowork_tahoe_member)
    host! "#{@operator.subdomain}.example.com"

    # Give the operator a second location so current_location can't auto-resolve
    # -- this is what makes Untethered different from the other three brands.
    @operator.locations.create!(
      locations(:cowork_tahoe_location).attributes
        .except("id", "created_at", "updated_at", "slug")
        .merge("name" => "Second Location"),
    )
    assert_operator @operator.locations.count, :>, 1

    @user.create_reset_digest
    @token = @user.reset_token
  end

  test "logged-out visitor can load the forgot-password form on a multi-location operator" do
    get new_password_reset_path, env: default_env

    assert_response :success
  end

  test "logged-out visitor can open a reset link on a multi-location operator" do
    get edit_password_reset_path(@token, email: @user.email), env: default_env

    assert_response :success
  end

  test "logged-out visitor can complete a reset on a multi-location operator" do
    patch password_reset_path(@token),
          params: { email: @user.email, user: { password: "brandnew123", password_confirmation: "brandnew123" } },
          env: default_env

    assert_redirected_to root_path
    assert @user.reload.authenticate("brandnew123")
  end
end
