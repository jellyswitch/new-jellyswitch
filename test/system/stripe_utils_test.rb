require "test_helper"

class StripeUtilsTest < ActiveSupport::TestCase
  include StripeUtils

  test "update_customer_email updates the customer email correctly" do
    user = users(:cowork_tahoe_admin)
    new_email = "new_email@example.com"

    # Stub the retrieve_stripe_customer method to return a mock customer object
    mock_customer = mock("Stripe::Customer")
    mock_customer.expects(:email=).with(new_email)
    mock_customer.expects(:save)
    self.expects(:retrieve_stripe_customer).with(user).returns(mock_customer)

    update_customer_email(user, new_email)
  end
end
