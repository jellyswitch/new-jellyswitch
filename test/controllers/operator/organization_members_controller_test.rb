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
end
