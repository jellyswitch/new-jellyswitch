require "test_helper"

class Api::V1::Admin::InvoicesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin    = users(:cowork_tahoe_admin)
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)

    @token = JWT.encode(
      { user_id: @admin.id, operator_id: @operator.id, exp: 30.days.from_now.to_i },
      Rails.application.secret_key_base,
      "HS256",
    )
  end

  def headers
    {
      "Authorization"        => "Bearer #{@token}",
      "X-Operator-Subdomain" => @operator.subdomain,
      "Content-Type"         => "application/json",
    }
  end

  def create_open_invoice(operator: @operator, location: @location)
    Invoice.create!(
      billable: users(:cowork_tahoe_member),
      operator: operator,
      location: location,
      amount_due: 12000,
      amount_paid: 0,
      status: "open",
    )
  end

  # "We received their check/ACH." The endpoint used to flip status only,
  # leaving amount_paid = 0 and no date — so the payment never appeared in
  # any revenue number.
  test "mark_paid stamps date and amount_paid so revenue counts the payment" do
    invoice = create_open_invoice

    post "/api/v1/admin/invoices/#{invoice.id}/mark_paid", headers: headers
    assert_response :success

    invoice.reload
    assert_equal "paid", invoice.status
    assert_equal 12000, invoice.amount_paid
    assert_not_nil invoice.date

    # And the reports math actually sees it now
    report = Jellyswitch::Report.new(@operator, @location)
    range = Date.current.beginning_of_month..Date.current.end_of_month
    assert_operator report.revenue_for_period(range: range), :>=, 120
  end

  test "mark_paid cannot touch another operator's invoice" do
    other_operator = Operator.create!(name: "Other Space", subdomain: "otherspace-test")
    foreign_invoice = Invoice.create!(
      billable: users(:cowork_tahoe_member),
      operator: other_operator,
      amount_due: 9999,
      status: "open",
    )

    post "/api/v1/admin/invoices/#{foreign_invoice.id}/mark_paid", headers: headers

    assert_response :not_found
    assert_equal "open", foreign_invoice.reload.status
  end
end
