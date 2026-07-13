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

  # Regression: the untethered /login 500. On a MULTI-location operator with
  # no location chosen, current_location is legitimately nil (the picker is
  # the next stop) — but a logged-in member's nav called allowed_in?(nil),
  # which raised NoMethodError in Checkin.for_location (nil.id).
  test "GET /login while logged in with no chosen location does not 500" do
    Location.create!(name: "Annex", operator: @operator,
                     working_day_start: "06:00", working_day_end: "20:00")
    member = users(:cowork_tahoe_member)
    member.update!(current_location: nil)

    log_in member
    get "/login", env: default_env

    assert_response :success
  end
end
