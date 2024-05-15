require "stripe_mock"
require "test_helper"

class Billing::Payment::SetToCreditCardTest < ActiveSupport::TestCase
  include StripeHelper

  setup do
    StripeMock.start
    setup_initial_user_fixtures
    @user = users(:cowork_tahoe_member)

    setup_stripe
  end

  teardown do
    StripeMock.stop
  end

  test "should set billing to charge_automatically" do
    Billing::Payment::SetToCreditCard.call(user: @user)

    @user.subscriptions_billable.active.each do |subscription|
      assert_equal "charge_automatically", subscription.stripe_subscription.billing
    end
  end

  test "should update user attributes" do
    Billing::Payment::SetToCreditCard.call(user: @user)

    assert @user.card_added
    assert_not @user.out_of_band
    assert_not @user.bill_to_organization
  end

  test "should fail if user update fails" do
    @user.stub(:update, false) do
      result = Billing::Payment::SetToCreditCard.call(user: @user)

      assert result.failure?
      assert_equal "An error occurred.", result.message
    end
  end
end
