require "test_helper"

class Api::V1::InvoicesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @operator = operators(:cowork_tahoe)
    @member = users(:cowork_tahoe_member)
    @invoice = invoices(:member_invoice)
    # Avoid live Stripe lookups from description/pdf_url in the JSON payload
    Invoice.where(billable: @member)
           .update_all(stripe_invoice_id: nil, stripe_payment_intent_id: nil)
  end

  def headers(user: @member)
    token = JWT.encode(
      { user_id: user.id, operator_id: @operator.id, exp: 30.days.from_now.to_i },
      Rails.application.secret_key_base,
      "HS256",
    )
    {
      "Authorization"        => "Bearer #{token}",
      "X-Operator-Subdomain" => @operator.subdomain,
    }
  end

  test "index renders the member's invoices" do
    get "/api/v1/invoices", headers: headers
    assert_response :success

    ids = JSON.parse(response.body).map { |i| i["id"] }
    assert_includes ids, @invoice.id
  end

  test "index does not 500 on an open invoice (can_charge regression)" do
    # has_billing_for_location? takes a location arg; the bare call only ran
    # for open invoices, 500ing every member with one.
    @invoice.update_columns(status: "open")

    get "/api/v1/invoices", headers: headers
    assert_response :success

    row = JSON.parse(response.body).find { |i| i["id"] == @invoice.id }
    assert_includes [true, false], row["can_charge"]
  end

  test "index handles an open invoice with no location" do
    @invoice.update_columns(status: "open", location_id: nil)

    get "/api/v1/invoices", headers: headers
    assert_response :success

    row = JSON.parse(response.body).find { |i| i["id"] == @invoice.id }
    assert_includes [true, false], row["can_charge"]
  end

  test "charge pays the member's own open invoice" do
    @invoice.update_columns(status: "open")

    Billing::Invoices::ChargeInvoice
      .expects(:call)
      .with(invoice: @invoice, operator: @operator)
      .returns(stub(success?: true))

    post "/api/v1/invoices/#{@invoice.id}/charge", headers: headers
    assert_response :success
    assert JSON.parse(response.body)["success"]
  end

  test "charge returns 403 for someone else's invoice" do
    Billing::Invoices::ChargeInvoice.expects(:call).never

    post "/api/v1/invoices/#{@invoice.id}/charge",
         headers: headers(user: users(:cowork_tahoe_non_member))
    assert_response :forbidden
  end

  test "charge surfaces an interactor failure as an error, not a 500" do
    @invoice.update_columns(status: "open")

    Billing::Invoices::ChargeInvoice
      .expects(:call)
      .returns(stub(success?: false, message: "Failed to mark invoice as paid."))

    post "/api/v1/invoices/#{@invoice.id}/charge", headers: headers
    assert_response :unprocessable_entity
    assert_equal "Failed to mark invoice as paid.", JSON.parse(response.body)["error"]
  end

  test "charge surfaces a Stripe error as an error, not a 500" do
    @invoice.update_columns(status: "open")

    Billing::Invoices::ChargeInvoice
      .expects(:call)
      .raises(Stripe::InvalidRequestError.new("Invoice is already paid", "invoice"))

    post "/api/v1/invoices/#{@invoice.id}/charge", headers: headers
    assert_response :unprocessable_entity
    assert_match(/Payment processing error/, JSON.parse(response.body)["error"])
  end

  test "charge returns 404 for a missing invoice" do
    post "/api/v1/invoices/0/charge", headers: headers
    assert_response :not_found
  end
end
