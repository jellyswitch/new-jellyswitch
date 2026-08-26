require "test_helper"

# Regression: the reset link's token was never verified. edit/update identified
# the user from the `email` query param alone and used params[:id] only to build
# the form's action URL, so anyone who knew a member's email could arm a reset
# and then set that member's password with a made-up token.
class Operator::PasswordResetsControllerTest < ActionDispatch::IntegrationTest
  setup do
    setup_initial_user_fixtures
    @operator = operators(:cowork_tahoe)
    @user = users(:cowork_tahoe_member)
    host! "#{@operator.subdomain}.example.com"

    @user.create_reset_digest
    @token = @user.reset_token
  end

  test "GET edit with a valid token renders the form" do
    get edit_password_reset_path(@token, email: @user.email), env: default_env

    assert_response :success
  end

  test "GET edit with a forged token does not render the form" do
    get edit_password_reset_path("not-the-real-token", email: @user.email), env: default_env

    assert_redirected_to new_password_reset_path
  end

  test "PATCH update with a forged token does not change the password" do
    original_digest = @user.password_digest

    patch password_reset_path("not-the-real-token"),
          params: { email: @user.email, user: { password: "hijacked123", password_confirmation: "hijacked123" } },
          env: default_env

    assert_redirected_to new_password_reset_path
    assert_equal original_digest, @user.reload.password_digest, "password must not change on a forged token"
    assert_nil session[:user_id], "a forged token must not log anyone in"
  end

  test "PATCH update with no reset ever requested does not change the password" do
    @user.update_columns(reset_digest: nil, reset_sent_at: nil)
    original_digest = @user.password_digest

    patch password_reset_path("anything"),
          params: { email: @user.email, user: { password: "hijacked123", password_confirmation: "hijacked123" } },
          env: default_env

    assert_redirected_to new_password_reset_path
    assert_equal original_digest, @user.reload.password_digest
  end

  test "PATCH update with a valid token resets the password and consumes the token" do
    patch password_reset_path(@token),
          params: { email: @user.email, user: { password: "brandnew123", password_confirmation: "brandnew123" } },
          env: default_env

    assert_redirected_to root_path
    @user.reload
    assert @user.authenticate("brandnew123"), "password should be updated"
    assert_nil @user.reset_digest, "token should be single-use"
    assert_nil @user.reset_sent_at
  end

  test "a consumed token cannot be replayed" do
    patch password_reset_path(@token),
          params: { email: @user.email, user: { password: "brandnew123", password_confirmation: "brandnew123" } },
          env: default_env

    patch password_reset_path(@token),
          params: { email: @user.email, user: { password: "replayed123", password_confirmation: "replayed123" } },
          env: default_env

    assert_redirected_to new_password_reset_path
    assert @user.reload.authenticate("brandnew123"), "replay must not take effect"
  end

  test "an expired token is rejected" do
    @user.update_column(:reset_sent_at, 3.hours.ago)

    get edit_password_reset_path(@token, email: @user.email), env: default_env

    assert_redirected_to new_password_reset_path
  end

  # Regression: find_user returned nil and check_expiration called
  # password_reset_expired? on it -> NoMethodError -> 500 on a public page.
  test "GET edit for an unknown email redirects instead of 500ing" do
    get edit_password_reset_path(@token, email: "nobody-#{SecureRandom.hex}@example.com"), env: default_env

    assert_redirected_to new_password_reset_path
  end

  test "GET edit with no email param redirects instead of 500ing" do
    get edit_password_reset_path(@token), env: default_env

    assert_redirected_to new_password_reset_path
  end
end
