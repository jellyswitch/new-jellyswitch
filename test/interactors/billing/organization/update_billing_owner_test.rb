require "test_helper"

class Billing::Organization::UpdateBillingOwnerTest < ActiveSupport::TestCase
  test "it updates the billing owner's email and calls update_customer_email" do
    organization = organizations(:sierra_nevada_organization)
    new_billing_owner = users(:cowork_tahoe_community_manager)
    operator = operators(:cowork_tahoe)

    # Assert that update_customer_email is called with the correct arguments
    operator.expects(:update_customer_email).with(organization, new_billing_owner.email)

    result = Billing::Organization::UpdateBillingOwner.call(
      organization: organization,
      new_billing_owner: new_billing_owner,
      operator: operator,
    )

    assert result.success?
  end

  test "it fails to update billing owner's email" do
    organization = organizations(:sierra_nevada_organization)
    new_billing_owner = users(:cowork_tahoe_community_manager)
    operator = operators(:cowork_tahoe)

    # Stub the update_customer_email method to raise an error
    operator.stub(:update_customer_email, ->(_, _) { raise StandardError.new("Some error") }) do
      result = Billing::Organization::UpdateBillingOwner.call(
        organization: organization,
        new_billing_owner: new_billing_owner,
        operator: operator,
      )

      assert_not result.success?
      assert_equal "Failed to update billing owner: Some error", result.message
    end
  end
end
