require "test_helper"

class InvoiceReceiptUrlTest < ActiveSupport::TestCase
  setup do
    @invoice = invoices(:paid_invoice)
  end

  test "subscription invoice resolves the receipt through the Stripe invoice's charge" do
    @invoice.stubs(:stripe_invoice).returns(OpenStruct.new(charge: "ch_123"))
    Stripe::Charge.expects(:retrieve).with("ch_123", anything)
                  .returns(OpenStruct.new(receipt_url: "https://pay.stripe.com/receipts/sub"))

    assert_equal "https://pay.stripe.com/receipts/sub", @invoice.receipt_url
  end

  test "PaymentIntent-backed invoice uses the charge receipt" do
    @invoice.update_columns(stripe_invoice_id: nil, stripe_payment_intent_id: "pi_123")
    @invoice.stubs(:stripe_charge_receipt_url).returns("https://pay.stripe.com/receipts/pi")

    assert_equal "https://pay.stripe.com/receipts/pi", @invoice.receipt_url
  end

  test "unpaid invoice has no receipt" do
    @invoice.update_columns(status: "open")
    Stripe::Charge.expects(:retrieve).never

    assert_nil @invoice.receipt_url
  end

  test "invoice paid out of band (no charge) has no receipt" do
    @invoice.stubs(:stripe_invoice).returns(OpenStruct.new(charge: nil))

    assert_nil @invoice.receipt_url
  end
end
