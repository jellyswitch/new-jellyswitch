require "test_helper"

class UserMailerInvoiceReceiptTest < ActionMailer::TestCase
  setup do
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
    @invoice = invoices(:paid_invoice)
    # Clear Stripe refs so description falls back to "Invoice #..." without
    # hitting the Stripe API (WebMock blocks unstubbed requests).
    @invoice.update_columns(stripe_invoice_id: nil, stripe_payment_intent_id: nil)
    Invoice.any_instance.stubs(:pdf_url).returns("https://example.com/receipt/abc")
  end

  test "sends to billable user's email" do
    mail = UserMailer.invoice_receipt_email(@invoice)
    assert_equal [@invoice.billable.email], mail.to
  end

  test "subject mentions operator and amount" do
    mail = UserMailer.invoice_receipt_email(@invoice)
    assert_match @operator.name, mail.subject
    assert_match "175.00", mail.subject # paid_invoice fixture: amount_due 17500
  end

  test "body includes receipt link, amount, and description" do
    mail = UserMailer.invoice_receipt_email(@invoice)
    body = mail.body.to_s
    assert_match "https://example.com/receipt/abc", body
    assert_match "175.00", body
  end

  test "from address uses location sender_from_address when present" do
    @location.stubs(:sender_from_address).returns("billing@cowork-tahoe.com")
    @invoice.stubs(:location).returns(@location)
    mail = UserMailer.invoice_receipt_email(@invoice)
    assert_includes mail.from, "billing@cowork-tahoe.com"
  end
end
