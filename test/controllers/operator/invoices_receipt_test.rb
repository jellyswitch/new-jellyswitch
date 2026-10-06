require "test_helper"

class Operator::InvoicesReceiptTest < ActionDispatch::IntegrationTest
  setup do
    @member = users(:cowork_tahoe_member)
    @invoice = invoices(:paid_invoice)
    Invoice.any_instance.stubs(:receipt_url).returns("https://pay.stripe.com/receipts/abc")
  end

  test "member is redirected to the Stripe receipt for their own paid invoice" do
    log_in @member
    get invoice_receipt_path(@invoice), env: default_env
    assert_redirected_to "https://pay.stripe.com/receipts/abc"
  end

  test "another member cannot open someone else's receipt" do
    log_in users(:cowork_tahoe_non_member)
    get invoice_receipt_path(@invoice), env: default_env
    refute_equal "https://pay.stripe.com/receipts/abc", response.location
  end

  test "flashes instead of redirecting when there is no card receipt" do
    Invoice.any_instance.stubs(:receipt_url).returns(nil)
    log_in @member
    get invoice_receipt_path(@invoice), env: default_env
    assert_match(/no card receipt/i, flash[:error].to_s)
  end

  test "member invoices page shows View Receipt on a paid invoice" do
    Invoice.any_instance.stubs(:stripe_invoice).returns(nil)
    log_in @member
    get user_invoices_path(@member), env: default_env
    assert_response :success
    assert_includes response.body, invoice_receipt_path(@invoice)
  end
end
