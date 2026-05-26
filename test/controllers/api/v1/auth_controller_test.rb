require "test_helper"

# End-to-end coverage for /api/v1/auth/*. These endpoints are the entry point
# for every mobile session, so regressions here lock users out of the app —
# hand-verifying with curl post-deploy (as we did for PR #437) is not a
# sustainable substitute.
class Api::V1::AuthControllerTest < ActionDispatch::IntegrationTest
  setup do
    @operator = operators(:cowork_tahoe)
    @user     = users(:cowork_tahoe_member)
    @password = "correct-horse-battery-staple"
    @user.update!(password: @password)
  end

  # ---------- POST /api/v1/auth/login ----------

  test "login with valid credentials returns a JWT and user payload" do
    post "/api/v1/auth/login",
         params: { subdomain: @operator.subdomain, email: @user.email, password: @password }

    assert_response :success
    body = JSON.parse(response.body)
    assert body["token"].present?, "expected JWT in response"
    assert_equal @user.id, body.dig("user", "id")
    assert_equal @user.email, body.dig("user", "email")

    # Token must be decodable with the same secret/algo the controller uses.
    payload = JWT.decode(body["token"], Rails.application.secret_key_base, true, algorithm: "HS256").first
    assert_equal @user.id, payload["user_id"]
    assert_equal @operator.id, payload["operator_id"]
  end

  test "login is case-insensitive on email" do
    post "/api/v1/auth/login",
         params: { subdomain: @operator.subdomain, email: @user.email.upcase, password: @password }

    assert_response :success
  end

  test "login with wrong password returns 401" do
    post "/api/v1/auth/login",
         params: { subdomain: @operator.subdomain, email: @user.email, password: "wrong" }

    assert_response :unauthorized
    assert_equal "Invalid email or password", JSON.parse(response.body)["error"]
  end

  test "login with unknown email returns 401, not 404" do
    post "/api/v1/auth/login",
         params: { subdomain: @operator.subdomain, email: "nobody@example.com", password: "anything" }

    assert_response :unauthorized
  end

  test "login with unknown subdomain returns 404" do
    post "/api/v1/auth/login",
         params: { subdomain: "does-not-exist", email: @user.email, password: @password }

    assert_response :not_found
  end

  # ---------- POST /api/v1/auth/signup ----------

  test "signup creates a user, returns a token, and defaults to a visible location" do
    assert_difference -> { @operator.users.count }, 1 do
      post "/api/v1/auth/signup",
           params: {
             subdomain: @operator.subdomain,
             name:      "New Member",
             email:     "new-member-#{SecureRandom.hex(4)}@example.com",
             password:  "abcdef",
             phone:     "555-0100",
           }
    end

    assert_response :created
    body = JSON.parse(response.body)
    assert body["token"].present?
    assert_equal "New Member", body.dig("user", "name")

    new_user = @operator.users.find(body.dig("user", "id"))
    assert new_user.original_location_id.present?,
      "signup must default to a visible location when none is passed"
    assert new_user.original_location.visible?,
      "signup default location must be visible (regression guard for hidden-location leak)"
  end

  test "signup with unknown subdomain returns 404" do
    post "/api/v1/auth/signup",
         params: { subdomain: "does-not-exist", name: "X", email: "x@example.com", password: "abcdef", phone: "555-0100" }

    assert_response :not_found
  end

  test "signup surfaces validation errors as 422" do
    post "/api/v1/auth/signup",
         params: {
           subdomain: @operator.subdomain,
           name:      "Dup",
           email:     @user.email, # already taken in this operator
           password:  "abcdef",
           phone:     "555-0100",
         }

    assert_response :unprocessable_entity
  end

  # ---------- POST /api/v1/auth/forgot_password ----------

  test "forgot_password returns success for a real email" do
    post "/api/v1/auth/forgot_password",
         params: { subdomain: @operator.subdomain, email: @user.email }

    assert_response :success
    assert_equal true, JSON.parse(response.body)["success"]
  end

  test "forgot_password returns success for an unknown email (no enumeration)" do
    post "/api/v1/auth/forgot_password",
         params: { subdomain: @operator.subdomain, email: "ghost@example.com" }

    assert_response :success
    assert_equal true, JSON.parse(response.body)["success"]
  end

  test "forgot_password returns 404 only when the subdomain itself is unknown" do
    post "/api/v1/auth/forgot_password",
         params: { subdomain: "does-not-exist", email: @user.email }

    assert_response :not_found
  end

  # ---------- GET /api/v1/auth/operators ----------

  test "operators index lists operators that have at least one visible location" do
    get "/api/v1/auth/operators"

    assert_response :success
    body = JSON.parse(response.body)
    op = body.fetch("operators").find { |o| o["subdomain"] == @operator.subdomain }
    refute_nil op, "expected #{@operator.subdomain} in operators index"
    assert op["primary_location_name"].present?
    assert op["locations"].is_a?(Array)
  end

  test "operators index excludes operators with no visible locations" do
    Location.where(operator: @operator).update_all(visible: false)

    get "/api/v1/auth/operators"

    assert_response :success
    body = JSON.parse(response.body)
    subdomains = body.fetch("operators").map { |o| o["subdomain"] }
    refute_includes subdomains, @operator.subdomain
  end

  # ---------- POST /api/v1/auth/lookup_operators ----------

  test "lookup_operators returns the operators a real email belongs to" do
    post "/api/v1/auth/lookup_operators", params: { email: @user.email }

    assert_response :success
    body = JSON.parse(response.body)
    subdomains = body.fetch("operators").map { |o| o["subdomain"] }
    assert_includes subdomains, @operator.subdomain
  end

  test "lookup_operators returns an empty list for an unknown email" do
    post "/api/v1/auth/lookup_operators", params: { email: "ghost@example.com" }

    assert_response :success
    assert_equal [], JSON.parse(response.body).fetch("operators")
  end

  test "lookup_operators returns an empty list when email is blank" do
    post "/api/v1/auth/lookup_operators", params: { email: "" }

    assert_response :success
    assert_equal [], JSON.parse(response.body).fetch("operators")
  end

  # ---------- POST /api/v1/auth/refresh ----------

  test "refresh without a token returns 401" do
    post "/api/v1/auth/refresh"
    assert_response :unauthorized
  end

  test "refresh with a valid token returns a new token" do
    token = JWT.encode(
      { user_id: @user.id, operator_id: @operator.id, exp: 30.days.from_now.to_i },
      Rails.application.secret_key_base,
      "HS256",
    )
    post "/api/v1/auth/refresh",
         headers: { "Authorization" => "Bearer #{token}", "X-Operator-Subdomain" => @operator.subdomain }

    assert_response :success
    body = JSON.parse(response.body)
    assert body["token"].present?
    assert_equal @user.id, body.dig("user", "id")
  end
end
