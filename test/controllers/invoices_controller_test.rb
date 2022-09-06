require "test_helper"

class InvoicesControllerTest < ActionDispatch::IntegrationTest

  setup do
    @user = users(:cowork_tahoe_admin)
    log_in @user
    @invoice = invoices(:member_invoice)
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