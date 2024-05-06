require "test_helper"

class UpdateOrganizationDetailsTest < ActiveSupport::TestCase
  def setup
    @organization = organizations(:sierra_nevada_organization)
    @owner = users(:cowork_tahoe_community_manager)

    @params = { name: "New Name", owner_id: @owner.id }
  end

  test "updates organization details" do
    result = UpdateOrganizationDetails.call(organization: @organization, params: @params)

    updated_organization = result.organization

    assert result.success?
    assert_equal updated_organization, @organization.reload
    assert_equal "New Name", updated_organization.name
    assert_equal @owner, updated_organization.owner
  end

  test "sets error message when organization fails to save" do
    @organization.stubs(:save).returns(false)
    @organization.stubs(:errors).returns(stub(full_messages: ["Something went wrong"]))

    result = UpdateOrganizationDetails.call(organization: @organization, params: @params)

    assert_not result.success?
    assert_equal "Failed to update organization details: Something went wrong", result.message
  end
end
