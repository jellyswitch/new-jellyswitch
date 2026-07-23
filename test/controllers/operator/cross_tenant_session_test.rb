require "test_helper"

# Regression: cross-tenant session leakage. The session cookie is domain-wide
# (`domain: :all` in config/initializers/sessions.rb — in test, `.lvh.me` —
# so one `_magic_session` spans every tenant subdomain), and
# SessionsHelper#current_user looked the user up with no tenant check. A member
# logged in on operator A's site was therefore silently logged in on operator
# B's site as their operator-A record. Real incident (2026-07-22): an
# Untethered member bought a Cowork Tahoe day pass while her Untethered session
# was active — the CT invoice + day pass got attached to the Untethered-tenant
# user, the CT admin couldn't view or approve them, and she paid twice.
#
# The fix treats a session user from another operator as logged OUT on that
# host WITHOUT touching the session or cookies, so the member stays logged in
# on their own tenant's site. Platform staff (the `superadmin` BOOLEAN, not the
# per-operator "superadmin" role) deliberately cross tenants, mirroring
# Api::V1::BaseController#enforce_tenant_scope!.
#
# These tests use `*.lvh.me` hosts so the integration cookie jar shares the
# session cookie across tenant subdomains exactly like production.
class Operator::CrossTenantSessionTest < ActionDispatch::IntegrationTest
  setup do
    setup_initial_user_fixtures
    @operator = operators(:cowork_tahoe)
    @member   = users(:cowork_tahoe_member)

    @other_operator = create(:operator)
    @other_location = create(:location, operator: @other_operator)

    host! own_host
  end

  def own_host
    "#{@operator.subdomain}.lvh.me"
  end

  def other_host
    "#{@other_operator.subdomain}.lvh.me"
  end

  # /approval_status is a tenant-scoped JSON probe of the session:
  # {approved: true} iff current_user resolves (and is approved) on this host.
  def approved_here?
    get "/approval_status", env: default_env
    assert_response :success
    response.parsed_body["approved"]
  end

  # Builds the same signed cookie value the app's `remember` helper would set.
  def signed_cookie_value(name, value)
    test_request = ActionDispatch::TestRequest.create
    jar = ActionDispatch::Cookies::CookieJar.build(test_request, {})
    jar.signed[name] = value
    jar[name]
  end

  # Plants the remember-me cookies domain-wide (like the session cookie) so we
  # can exercise the `cookies.signed[:user_id]` branch on a foreign host.
  def plant_remember_cookies(user)
    user.remember
    cookies.merge("user_id=#{Rack::Utils.escape(signed_cookie_value(:user_id, user.id))}; domain=.lvh.me; path=/")
    cookies.merge("remember_token=#{Rack::Utils.escape(user.remember_token)}; domain=.lvh.me; path=/")
  end

  test "session is honored on the member's own tenant" do
    log_in @member

    assert_equal true, approved_here?
    assert_equal @member.id, session[:user_id]
  end

  test "session from another tenant's site is ignored but NOT destroyed" do
    log_in @member

    host! other_host
    assert_equal false, approved_here?, "member must not be logged in on another operator's site"
    assert_equal @member.id, session[:user_id], "cross-tenant request must not clear the session"

    # Standing rule: never log members out of their own site. Back on their own
    # tenant, the same session still works.
    host! own_host
    assert_equal true, approved_here?
  end

  test "platform staff (superadmin boolean) may cross tenants" do
    staff = users(:cowork_tahoe_superadmin)
    staff.update!(superadmin: true)
    log_in staff

    host! other_host
    assert_equal true, approved_here?
  end

  test "per-operator superadmin ROLE does not cross tenants" do
    # The fixture has role "superadmin" but the platform-staff boolean is false.
    role_superadmin = users(:cowork_tahoe_superadmin)
    assert_not role_superadmin.superadmin, "fixture precondition"
    log_in role_superadmin

    host! other_host
    assert_equal false, approved_here?
  end

  test "session still honored on the app subdomain (no tenant)" do
    log_in @member

    host! "#{Rails.application.config.app_subdomain}.lvh.me"
    get "/", env: default_env

    assert_response :redirect
    assert_includes response.location, "#{@operator.subdomain}.lvh.me"
  end

  test "remember-me cookie logs the member in on their own tenant" do
    plant_remember_cookies(@member)

    assert_equal true, approved_here?
    assert_equal @member.id, session[:user_id]
  end

  test "remember-me cookie is ignored on another tenant's site" do
    original_location_id = @member.current_location_id
    plant_remember_cookies(@member)

    host! other_host
    assert_equal false, approved_here?
    assert_nil session[:user_id], "cross-tenant remember-me must not create a session"
    # The auto-login used to run log_in, which rewrote the member's
    # current_location to the other operator's location.
    assert_equal original_location_id, @member.reload.current_location_id
  end

  test "masquerade on own tenant still works end to end" do
    admin = users(:cowork_tahoe_admin)
    log_in admin

    post "/masquerade", params: { user_id: @member.id }, env: default_env
    assert_redirected_to "/masquerade/current"
    assert_equal @member.id, session[:user_id]
    assert_equal admin.id, session[:masquerade_by_user_id]

    # Browsing as the member works.
    assert_equal true, approved_here?

    delete "/masquerade", env: default_env
    assert_equal admin.id, session[:user_id], "stop masquerading must restore the admin"
  end

  test "platform staff can masquerade on a foreign tenant" do
    staff = users(:cowork_tahoe_superadmin)
    staff.update!(superadmin: true)
    other_member = create(:user,
                          operator: @other_operator,
                          original_location: @other_location,
                          current_location: @other_location)
    log_in staff

    host! other_host
    post "/masquerade", params: { user_id: other_member.id }, env: default_env
    assert_equal other_member.id, session[:user_id]

    assert_equal true, approved_here?

    delete "/masquerade", env: default_env
    assert_equal staff.id, session[:user_id]
  end
end
