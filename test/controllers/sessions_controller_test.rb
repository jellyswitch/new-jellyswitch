require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    setup_initial_user_fixtures
    # The superadmin /login routes live under the `app` subdomain.
    host! "#{Rails.application.config.app_subdomain}.example.com"
  end

  # Regression: bots/scanners POST to the apex /login with no `session` param.
  # Previously this raised NoMethodError ("undefined method `[]' for nil")
  # at `params[:session][:email].downcase` and surfaced as a 500.
  test "POST /login with no session param does not 500" do
    post "/login", env: default_env

    assert_response :redirect
  end

  test "POST /login with empty session hash does not 500" do
    post "/login", params: { session: {} }, env: default_env

    assert_response :redirect
  end

  # Same guard on the password step (real_login -> real_create), which also
  # dereferences params[:session][:email] / params[:session][:password].
  test "POST /real_login with no session param does not 500" do
    post "/real_login", env: default_env

    assert_response :redirect
  end

  test "POST /real_login with empty session hash does not 500" do
    post "/real_login", params: { session: {} }, env: default_env

    assert_response :redirect
  end

  # Regression: the "No such user found." branch of `create` redirected via the
  # undefined `new_session_path`, raising NameError instead of redirecting back
  # to the apex login form. Should redirect to operator_login_path.
  test "POST /login with an unknown admin email redirects to the login form" do
    post "/login",
         params: { session: { email: "nobody-#{SecureRandom.hex}@example.com", password: "x" } },
         env: default_env

    assert_response :redirect
    assert_redirected_to operator_login_path
  end

  # Same undefined `new_session_path` reference in `password_form`'s blank-user
  # branch (GET /password_form when session[:email] matches no superadmin).
  test "GET /password_form with no session user redirects to the login form" do
    get "/password_form", env: default_env

    assert_response :redirect
    assert_redirected_to operator_login_path
  end
end
