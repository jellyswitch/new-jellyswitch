require "test_helper"
require "ostruct"

# Authorization guard on org billing. Before manage_billing?, this action had
# only require_authentication and never authorized, so any authenticated member
# could change any org's card / out_of_band flag. manage_billing? = staff OR
# owner of THIS org (mirrors the mobile API's org.owner_id == user.id gate).
class Operator::OrganizationBillingControllerTest < ActionDispatch::IntegrationTest
  setup do
    setup_initial_user_fixtures
    @operator = operators(:cowork_tahoe)
    @admin    = users(:cowork_tahoe_admin)
    @org      = organizations(:sierra_nevada_organization)
  end

  test "a non-owner, non-staff member cannot change org billing" do
    member = create(:user, operator: @operator, original_location: locations(:cowork_tahoe_location))
    reached = false
    UpdateOrganizationBilling.stub(:call, ->(*_args, **_kw) { reached = true; OpenStruct.new(success?: true, message: nil) }) do
      log_in member
      post organization_billing_path(@org), params: { out_of_band: "1" }, env: default_env
    end
    assert_not reached, "a non-owner, non-staff member must not reach the billing update"
    assert_response :redirect
  end

  test "staff (admin) can change org billing" do
    reached = false
    UpdateOrganizationBilling.stub(:call, ->(*_args, **_kw) { reached = true; OpenStruct.new(success?: true, message: nil) }) do
      log_in @admin
      post organization_billing_path(@org), params: { out_of_band: "1" }, env: default_env
    end
    assert reached, "staff should reach the billing update"
  end

  test "the organization owner (non-staff) can change their own org billing" do
    owner = create(:user, operator: @operator, original_location: locations(:cowork_tahoe_location))
    @org.update!(owner: owner)
    reached = false
    UpdateOrganizationBilling.stub(:call, ->(*_args, **_kw) { reached = true; OpenStruct.new(success?: true, message: nil) }) do
      log_in owner
      post organization_billing_path(@org), params: { out_of_band: "1" }, env: default_env
    end
    assert reached, "the owner of THIS org should reach the billing update"
  end
end
