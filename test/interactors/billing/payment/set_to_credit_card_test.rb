require "stripe_mock"
require "test_helper"

class Billing::Payment::SetToCreditCardTest < ActiveSupport::TestCase
  include StripeHelper

  setup do
    StripeMock.start
    setup_initial_user_fixtures
    @user = users(:cowork_tahoe_member)
    @location = locations(:cowork_tahoe_location)

    setup_stripe
  end

  teardown do
    StripeMock.stop
  end

  # StripeMock cannot serve a connected-account retrieve (stripe_request passes
  # stripe_account), so stand in for what Stripe would report about the card.
  def attach_card!
    @user.stubs(:card_last_4_digits).with(@location).returns("4242")
  end

  test "should set billing to charge_automatically" do
    Billing::Payment::SetToCreditCard.call(user: @user, location: @location)

    @user.subscriptions_billable.active.each do |subscription|
      assert_equal "charge_automatically", subscription.stripe_subscription.billing
    end
  end

  test "should update user attributes when a card is on file" do
    attach_card!
    Billing::Payment::SetToCreditCard.call(user: @user, location: @location)

    assert @user.card_added
    assert @user.card_added_for_location?(@location)
    assert_not @user.out_of_band
    assert_not @user.bill_to_organization
  end

  # The only exit from out-of-band. Staff who flip a card-less member to
  # out-of-band by mistake must be able to flip back before a card exists.
  test "clears out_of_band for a member with no card, without claiming a card" do
    @user.update!(out_of_band: true, card_added: false)

    result = Billing::Payment::SetToCreditCard.call(user: @user, location: @location)

    assert result.success?
    assert_not @user.reload.out_of_band
    assert_not @user.card_added
    assert_not @user.card_added_for_location?(@location)
  end

  test "should fail if user update fails" do
    @user.stub(:update, false) do
      result = Billing::Payment::SetToCreditCard.call(user: @user, location: @location)

      assert result.failure?
      assert_equal "Unable to update payment method: ", result.message
    end
  end
end
