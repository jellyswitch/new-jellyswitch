require "test_helper"

# Recording an out-of-band payment (check/ACH) must stamp the fields revenue
# reads. Previously this only flipped status: the row kept amount_paid = 0
# forever, and a row with no date never appeared in any revenue window.
class Billing::Invoices::MarkInvoiceAsPaidTest < ActiveSupport::TestCase
  setup do
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
  end

  test "marks a local (non-Stripe) invoice paid and stamps date and amount_paid" do
    invoice = Invoice.create!(
      billable: users(:cowork_tahoe_member),
      operator: @operator,
      location: @location,
      amount_due: 15000,
      amount_paid: 0,
      status: "open",
    )
    assert_nil invoice.date

    result = Billing::Invoices::MarkInvoiceAsPaid.call(invoice: invoice, operator: @operator)

    assert result.success?
    invoice.reload
    assert_equal "paid", invoice.status
    assert_equal 15000, invoice.amount_paid
    assert_not_nil invoice.date, "a dateless paid invoice is invisible to revenue"
    assert_in_delta Time.current.to_i, invoice.date.to_i, 60
  end

  test "does not overwrite an existing invoice date" do
    original_date = 2.weeks.ago
    invoice = Invoice.create!(
      billable: users(:cowork_tahoe_member),
      operator: @operator,
      location: @location,
      amount_due: 9000,
      status: "open",
      date: original_date,
    )

    result = Billing::Invoices::MarkInvoiceAsPaid.call(invoice: invoice, operator: @operator)

    assert result.success?
    assert_in_delta original_date.to_i, invoice.reload.date.to_i, 1
  end

  test "fails when the invoice is already paid" do
    invoice = Invoice.create!(
      billable: users(:cowork_tahoe_member),
      operator: @operator,
      location: @location,
      amount_due: 5000,
      status: "paid",
      date: Time.current,
    )

    result = Billing::Invoices::MarkInvoiceAsPaid.call(invoice: invoice, operator: @operator)

    assert_not result.success?
  end
end
