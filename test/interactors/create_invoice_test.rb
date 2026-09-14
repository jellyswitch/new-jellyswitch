require "test_helper"

class CreateInvoiceTest < ActiveSupport::TestCase
  test "should create invoice successfully" do
    operator = operators(:cowork_tahoe)
    location = locations(:cowork_tahoe_location)
    user = users(:cowork_tahoe_member)

    stripe_invoice = OpenStruct.new(
      id: "in_1H9J9v2eZvKYlo2C5",
      amount_due: 1000,
      amount_paid: 0,
      customer: user.stripe_customer_id_for_location(location),
      created: Time.now.to_i,
      due_date: Time.now.to_i + 30.days,
      status: "open"
    )

    Billing::Invoices::AddCreditsToSubscribable.expects(:call).with(anything).returns(OpenStruct.new(success?: true))

    result = CreateInvoice.call(stripe_invoice: stripe_invoice)

    assert result.success?
    assert result.invoice.persisted?
    assert result.invoice.location == location
  end

  test "webhook invoice takes its location from the Stripe customer's payment profile when the user has no current_location" do
    location = locations(:cowork_tahoe_location)
    user = users(:cowork_tahoe_member)
    profile = user_payment_profiles(:cowork_tahoe_member_payment_profile)
    profile.update!(stripe_customer_id: "cus_no_current_location")
    user.update_columns(current_location_id: nil)

    stripe_invoice = OpenStruct.new(
      id: "in_no_current_location",
      amount_due: 1000,
      amount_paid: 0,
      customer: "cus_no_current_location",
      created: Time.now.to_i,
      due_date: nil,
      status: "open"
    )

    # The webhook's Stripe invoice is handed through so credits don't re-fetch it.
    Billing::Invoices::AddCreditsToSubscribable
      .expects(:call)
      .with { |args| args[:stripe_invoice] == stripe_invoice }
      .returns(OpenStruct.new(success?: true))

    result = CreateInvoice.call(stripe_invoice: stripe_invoice)

    assert result.success?
    assert_equal location, result.invoice.location
  end
end
