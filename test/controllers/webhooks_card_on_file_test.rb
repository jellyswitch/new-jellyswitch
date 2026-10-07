require "test_helper"

# A member who saves their card while paying ends up with a card in Stripe but
# card_added=false locally; a successful card charge should heal the flag.
class WebhooksCardOnFileTest < ActionDispatch::IntegrationTest
  setup do
    host! "#{Rails.application.config.app_subdomain}.example.com"
    @location = locations(:cowork_tahoe_location)
    @user = users(:cowork_tahoe_member)
    @profile = @user.payment_profile_for_location(@location)
    @profile.update!(stripe_customer_id: "cus_wilson", card_added: false)
    @user.update_columns(card_added: false)
    Location.any_instance.stubs(:retrieve_stripe_customer).returns(OpenStruct.new(id: "cus_wilson"))
  end

  def post_charge(customer: "cus_wilson", account: @location.stripe_user_id, type: "card")
    payload = {
      id: "evt_test", object: "event", type: "charge.succeeded", account: account,
      data: { object: { id: "ch_test", object: "charge", customer: customer,
                        payment_method_details: { type: type } } },
    }
    post "/webhooks/stripe", params: payload.to_json,
                             headers: { "CONTENT_TYPE" => "application/json" }
    assert_response :success
  end

  test "marks the card on file when Stripe holds a saved card" do
    Location.any_instance.stubs(:first_card_for).returns(Struct.new(:last4).new("0295"))

    post_charge

    assert @profile.reload.card_added
    assert @user.reload.card_added
  end

  test "leaves the flag alone when the charge did not save a card" do
    Location.any_instance.stubs(:first_card_for).returns(nil)

    post_charge

    assert_not @profile.reload.card_added
  end

  test "ignores charges on another connected account" do
    Location.any_instance.expects(:first_card_for).never

    post_charge(account: "acct_someone_else")

    assert_not @profile.reload.card_added
  end

  test "ignores non-card charges" do
    Location.any_instance.expects(:first_card_for).never

    post_charge(type: "us_bank_account")

    assert_not @profile.reload.card_added
  end
end
