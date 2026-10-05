require "test_helper"

# "Access only" people (couriers, cleaning staff) are hidden from the member
# lists on web and mobile admin, listed on their own People > Access only tab,
# and toggled by staff from the user edit form / mobile admin API.
class AccessOnlyPeopleTest < ActionDispatch::IntegrationTest
  setup do
    setup_initial_user_fixtures
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
    @admin    = users(:cowork_tahoe_admin)
    ActsAsTenant.with_tenant(@operator) do
      @courier = create(:user, operator: @operator, name: "Courier Carl", email: "courier@example.com",
                        phone: "530-555-0199", access_only: true,
                        original_location: @location, current_location: @location)
    end
    @token = JWT.encode({ user_id: @admin.id, operator_id: @operator.id, exp: 30.days.from_now.to_i },
                        Rails.application.secret_key_base, "HS256")
  end

  def api_headers
    { "Authorization" => "Bearer #{@token}", "X-Operator-Subdomain" => @operator.subdomain,
      "Content-Type" => "application/json" }
  end

  # ── mobile admin API ──────────────────────────────────────────────────────

  test "mobile admin members index leaves access-only people out" do
    get "/api/v1/admin/members", headers: api_headers
    assert_response :success
    names = JSON.parse(response.body).map { |u| u["name"] }
    assert_includes names, "Tim C"
    assert_not_includes names, "Courier Carl"
  end

  test "mobile admin people index leaves access-only people out" do
    get "/api/v1/admin/people", headers: api_headers
    assert_response :success
    names = JSON.parse(response.body)["people"].map { |p| p["name"] }
    assert_includes names, "Tim C"
    assert_not_includes names, "Courier Carl"
  end

  test "mobile admin member show returns access_only and update toggles it" do
    get "/api/v1/admin/members/#{@courier.id}", headers: api_headers
    assert_response :success
    assert_equal true, JSON.parse(response.body)["access_only"]

    patch "/api/v1/admin/members/#{@courier.id}", params: { access_only: false }.to_json, headers: api_headers
    assert_response :success
    assert_equal false, JSON.parse(response.body)["access_only"]
    assert_not @courier.reload.access_only?
  end

  # ── web ───────────────────────────────────────────────────────────────────

  test "web People default list leaves access-only people out" do
    log_in @admin
    get people_path, env: default_env
    assert_response :success
    assert_includes response.body, "Tim C"
    assert_not_includes response.body, "Courier Carl"
  end

  test "web People > Access only lists them with email and phone" do
    log_in @admin
    get people_path(stage: "access_only"), env: default_env
    assert_response :success
    assert_includes response.body, "Courier Carl"
    assert_includes response.body, "courier@example.com"
    assert_includes response.body, "530-555-0199"
    assert_not_includes response.body, "Tim C"
  end

  test "web members list leaves access-only people out" do
    log_in @admin
    get users_path, env: default_env
    assert_response :success
    assert_not_includes response.body, "Courier Carl"
  end

  test "staff edit form shows the checkbox and saves the flag" do
    member = users(:cowork_tahoe_member)
    log_in @admin
    get edit_user_path(member), env: default_env
    assert_response :success
    assert_includes response.body, "Access only (couriers, cleaning, etc.)"

    patch user_path(member), params: { user: { access_only: "1" } }, env: default_env
    assert member.reload.access_only?
  end

  test "a member cannot make themselves access-only" do
    member = users(:cowork_tahoe_member)
    log_in member
    patch user_path(member), params: { user: { name: "Tim C", access_only: "1" } }, env: default_env
    assert_not member.reload.access_only?
  end
end
