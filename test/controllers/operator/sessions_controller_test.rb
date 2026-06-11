require "test_helper"

class Operator::SessionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    setup_initial_user_fixtures
    @operator = operators(:cowork_tahoe)
    @admin    = users(:cowork_tahoe_admin)
    host! "#{@operator.subdomain}.example.com"
  end

  # Regression: bots/scanners POST to /login with no `session` param.
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

  test "POST /login with bad credentials still flashes and redirects" do
    post "/login",
      params: { session: { email: @admin.email, password: "wrong-password" } },
      env: default_env

    assert_response :redirect
    assert_not_nil flash[:error]
  end
end
