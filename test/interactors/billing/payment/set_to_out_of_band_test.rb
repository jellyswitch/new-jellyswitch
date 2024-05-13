require "stripe_mock"
require "test_helper"

class Billing::Payment::SetToOutOfBandTest < ActiveSupport::TestCase
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

  test "should set billing to send_invoice and days_until_due to 30 for active subscriptions" do
    Billing::Payment::SetToOutOfBand.call(user: @user)

    @user.subscriptions_billable.active.each do |subscription|
      assert_equal "send_invoice", subscription.stripe_subscription.billing
      assert_equal 30, subscription.stripe_subscription.days_until_due
    end
  end

  test "should update user attributes" do
    Billing::Payment::SetToOutOfBand.call(user: @user)

    assert_not @user.card_added
    assert @user.out_of_band
    assert_not @user.bill_to_organization
  end

  test "should fail if user update fails" do
    @user.stub(:update, false) do
      result = Billing::Payment::SetToOutOfBand.call(user: @user)

      assert result.failure?
      assert_equal "An error occurred.", result.message
    end
  end
end
