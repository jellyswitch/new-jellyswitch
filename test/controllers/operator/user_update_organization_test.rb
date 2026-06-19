require "test_helper"

# The member-detail "Update group" form (operator/users#update_organization).
# A user reported "added a member to the group in web, but it didn't take" —
# the form was submitted with the blank default selected, writing
# organization_id = nil while still flashing a generic "Updated organization."
# success. These tests pin the real behavior and the clearer messaging.
class Operator::UserUpdateOrganizationTest < ActionDispatch::IntegrationTest
  setup do
    setup_initial_user_fixtures
    @operator = operators(:cowork_tahoe)
    @admin    = users(:cowork_tahoe_admin)
    @org      = organizations(:sierra_nevada_organization)
    @target   = users(:cowork_tahoe_non_member)
    @target.update_columns(organization_id: nil)
  end

  test "selecting a real org persists organization_id (server is correct)" do
    log_in @admin
    patch user_update_organization_path(@target),
         params: { user: { organization_id: @org.id } }, env: default_env
    assert_equal @org.id, @target.reload.organization_id
  end

  test "submitting blank reads as a removal, not a vague success" do
    @target.update_columns(organization_id: @org.id)
    log_in @admin
    patch user_update_organization_path(@target),
         params: { user: { organization_id: "" } }, env: default_env
    assert_nil @target.reload.organization_id
    # Message must reflect what actually happened (removal), not imply the
    # member was added to a group.
    assert_match(/removed|no group|not in/i, flash[:success].to_s)
  end

  test "adding to an org names the group in the flash" do
    log_in @admin
    patch user_update_organization_path(@target),
         params: { user: { organization_id: @org.id } }, env: default_env
    assert_match(/#{@org.name}/i, flash[:success].to_s)
  end
end
