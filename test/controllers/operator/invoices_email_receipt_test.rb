require "test_helper"

class Operator::InvoicesEmailReceiptTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:cowork_tahoe_admin)
    @member = users(:cowork_tahoe_member)
    @invoice = invoices(:paid_invoice)
    Invoice.any_instance.stubs(:pdf_url).returns("https://example.com/receipt/abc")
  end

  test "admin can email receipt for paid invoice" do
    log_in @admin
    assert_enqueued_emails 1 do
      post invoice_email_receipt_path(@invoice), env: default_env
    end
    assert_response :redirect
    assert_match(/Receipt emailed/i, flash[:success].to_s)
  end

  test "non-admin member cannot email receipt" do
    log_in @member
    assert_no_enqueued_emails do
      post invoice_email_receipt_path(@invoice), env: default_env
    end
    # Pundit forbidden returns a redirect with a flash error or a 403
    refute_equal 200, response.status
  end

  test "email_receipt errors gracefully when invoice is not paid" do
    @invoice.update_columns(status: "open")
    log_in @admin
    assert_no_enqueued_emails do
      post invoice_email_receipt_path(@invoice), env: default_env
    end
    assert_match(/only.*paid/i, flash[:error].to_s)
  end

  test "email_receipt errors gracefully when billable has no email" do
    @member.update_columns(email: "")
    log_in @admin
    assert_no_enqueued_emails do
      post invoice_email_receipt_path(@invoice), env: default_env
    end
    assert_match(/no email/i, flash[:error].to_s)
  end
end
