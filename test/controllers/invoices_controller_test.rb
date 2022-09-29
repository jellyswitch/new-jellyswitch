require "test_helper"

class InvoicesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:cowork_tahoe_admin)
    log_in @user
    @invoices = [invoices(:paid_invoice), invoices(:member_invoice)]
    StripeMock.start

    @invoices.map do |invoice|
      stripe_invoice = Stripe::Invoice.create(
        customer: @user.stripe_customer_id,
        currency: 'usd',
        amount: invoice.amount_due,
        description: 'test invoice'
      )
      
      invoice.update(stripe_invoice_id: stripe_invoice.id)
    end
    Invoice.any_instance.stubs(:payment_method).returns("Credit Card")
  end

  test "should get invoice index" do    
    get invoices_path, env: default_env
    assert_response :success
  end

  test "should get recent invoices" do
    get recent_invoices_path, env: default_env
    assert_response :success
  end

  test "should get delinquent invoices" do
    get delinquent_invoices_path, env: default_env
    assert_response :success
  end

  test "should get groups invoices" do
    get groups_invoices_path, env: default_env
    assert_response :success
  end

  test "should get open invoices path" do
    get open_invoices_path, env: default_env
    assert_response :success
  end
end