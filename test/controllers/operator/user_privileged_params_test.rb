require "test_helper"

# Security (found 10/5): a member editing their own profile could PATCH
# role / admin / approved / always_allow_building_access, because
# UserPolicy#update? lets users update themselves and UsersHelper#user_params
# permitted those keys for everyone. Only staff of the location may set them.
class Operator::UserPrivilegedParamsTest < ActionDispatch::IntegrationTest
  setup do
    setup_initial_user_fixtures
    @member = users(:cowork_tahoe_member)
    @admin  = users(:cowork_tahoe_admin)
    @member.update_columns(role: "unassigned", admin: false, always_allow_building_access: false)
    @user = @member # setup_stripe works on @user
    StripeMock.start
    setup_stripe
  end

  teardown { StripeMock.stop }

  test "a member cannot make themselves admin or grant themselves door access" do
    log_in @member
    patch user_path(@member, params: { user: {
      name: "Still Me", role: "superadmin", admin: true, approved: true, always_allow_building_access: true,
    } }), env: default_env

    @member.reload
    assert_equal "Still Me", @member.name            # ordinary fields still save
    assert_equal "unassigned", @member.role
    assert_not @member.admin?
    assert_not @member.always_allow_building_access?
  end

  test "staff can still set door access and approval on a member" do
    log_in @admin
    patch user_path(@member, params: { user: { always_allow_building_access: true, approved: true } }), env: default_env

    @member.reload
    assert @member.always_allow_building_access?
    assert @member.approved?
  end
end
