require "test_helper"

# Repro for "added a member to the group in web, but organization_id stayed
# nil." Isolates whether the SERVER persists when given valid user ids — if
# this passes, the no-op is in the form/JS, not the controller.
class Operator::OrganizationMembersControllerTest < ActionDispatch::IntegrationTest
  setup do
    setup_initial_user_fixtures
    @operator = operators(:cowork_tahoe)
    @admin    = users(:cowork_tahoe_admin)
    @org      = organizations(:sierra_nevada_organization)
    @target   = users(:cowork_tahoe_non_member)
    @target.update_columns(organization_id: nil) # precondition: not in any org
  end

  test "admin adds a member: organization_id is persisted" do
    assert_nil @target.reload.organization_id, "precondition: target not in an org"
    log_in @admin
    post organization_add_member_path(@org),
         params: { user: { ids: [@target.id] } }, env: default_env
    assert_equal @org.id, @target.reload.organization_id
  end

  test "blank ids are a no-op with an error flash (not a 500)" do
    log_in @admin
    post organization_add_member_path(@org),
         params: { user: { ids: [""] } }, env: default_env
    assert_response :redirect
  end

  # Cross-tenant write guard: the add-member form is correctly tenant-scoped
  # (`current_tenant.users` in add_member_options), but the controller update
  # must be too. An operator admin POSTing a user id belonging to ANOTHER
  # operator must not be able to pull that user into their organization —
  # User has no acts_as_tenant, so an unscoped `User.where(id: ids)` would
  # silently reassign the foreign user's organization_id.
  test "cannot move a user from another operator into this org" do
    other_operator = create(:operator)
    other_location = create(:location, operator: other_operator)
    foreign_user = create(:user,
      operator: other_operator,
      original_location: other_location,
      organization_id: nil)

    log_in @admin # scoped to @operator (cowork_tahoe) via ActsAsTenant.default_tenant
    post organization_add_member_path(@org),
         params: { user: { ids: [foreign_user.id] } }, env: default_env

    assert_nil foreign_user.reload.organization_id,
      "operator admin must not be able to add a foreign-operator user to their org"
  end
end
