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
end