require 'test_helper'

class RefundsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:cowork_tahoe_admin)
    @paid_invoice = invoices(:paid_invoice)
    log_in @user
  end

  test "should refund the paid invoice and redirect back to index (web)" do
    post invoice_refunds_path(invoice_id: @paid_invoice.id), env: default_env
    assert_redirected_to root_path(@user)
  end

  test "should refund the paid invoice and redirect back to index (iOS)" do
    post invoice_refunds_path(invoice_id: @paid_invoice.id), env: ios_env
    assert_redirected_to root_path(@user)
  end
end
