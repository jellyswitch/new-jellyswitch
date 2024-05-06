require "test_helper"

class StripeUtilsTest < ActiveSupport::TestCase
  include StripeUtils

  test "update_organization_customer_details updates the customer details correctly" do
    organization = organizations(:sierra_nevada_organization)
    new_email = "new_email@example.com"

    # Stub the retrieve_stripe_customer method to return a mock customer object
    mock_customer = mock("Stripe::Customer")
    mock_customer.expects(:email=).with(new_email)
    mock_customer.expects(:name=).with(organization.name) # Add this line
    mock_customer.expects(:save)
    self.expects(:retrieve_stripe_customer).with(organization).returns(mock_customer)

    update_organization_customer_details(organization, new_email)
  end
end
