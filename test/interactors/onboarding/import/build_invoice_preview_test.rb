require "test_helper"

class Onboarding::Import::BuildInvoicePreviewTest < ActiveSupport::TestCase
  setup do
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
    @member = users(:cowork_tahoe_member) # tim@jellyswitch.com
    @cm = {
      stripe_invoice_id: "Stripe Invoice", email: "Email", number: "Invoice #",
      amount_due: "Amount Due", amount_paid: "Amount Paid", status: "Status",
      date: "Date", due_date: "Due Date",
    }
    ActsAsTenant.current_tenant = @operator
  end

  teardown { ActsAsTenant.current_tenant = nil }

  def preview(rows, amount_format: :dollars)
    Onboarding::Import::BuildInvoicePreview.call(
      location: @location, rows: rows, column_mapping: @cm, amount_format: amount_format,
    )
  end

  test "fails without a location" do
    assert Onboarding::Import::BuildInvoicePreview.call(location: nil, rows: []).failure?
  end

  test "resolves a billable by email and parses amounts/status" do
    rows = [{ "Email" => "tim@jellyswitch.com", "Invoice #" => "A-100",
              "Amount Due" => "$25.00", "Amount Paid" => "25.00", "Status" => "Paid" }]
    row = preview(rows).preview[:rows].first

    assert_equal :user, row[:billable_match]
    assert_equal @member.id, row[:billable_id]
    assert_equal 2500, row[:amount_due_cents]
    assert_equal "paid", row[:status]
    assert_nil row[:error]
    refute row[:exists]
  end

  test "flags an unresolvable billable as an error" do
    rows = [{ "Email" => "nobody@example.com", "Amount Due" => "10.00" }]
    row = preview(rows).preview[:rows].first

    assert_equal :none, row[:billable_match]
    assert_match(/billable not found/, row[:error])
    assert_equal 1, preview(rows).preview[:summary][:errors]
  end

  test "flags an unparseable amount as an error" do
    rows = [{ "Email" => "tim@jellyswitch.com", "Amount Due" => "twenty bucks" }]
    row = preview(rows).preview[:rows].first
    assert_match(/amount_due/, row[:error])
  end

  test "warns on an unrecognized status and defaults to open" do
    rows = [{ "Email" => "tim@jellyswitch.com", "Amount Due" => "1.00", "Status" => "limbo" }]
    row = preview(rows).preview[:rows].first
    assert_equal "open", row[:status]
    assert(row[:warnings].any? { |w| w.include?("unrecognized status") })
  end

  test "detects an already-imported invoice by stripe id" do
    Invoice.create!(billable: @member, operator_id: @operator.id, location_id: @location.id,
                    stripe_invoice_id: "in_EXIST1", amount_due: 100, amount_paid: 100, status: "paid")

    rows = [{ "Email" => "tim@jellyswitch.com", "Stripe Invoice" => "in_EXIST1",
              "Amount Due" => "1.00", "Status" => "Paid" }]
    result = preview(rows)

    assert result.preview[:rows].first[:exists]
    assert_equal 1, result.preview[:summary][:existing]
    assert_equal 0, result.preview[:summary][:new]
  end

  test "summarizes total amount due across creatable rows" do
    rows = [
      { "Email" => "tim@jellyswitch.com", "Amount Due" => "10.00", "Status" => "Paid" },
      { "Email" => "tim@jellyswitch.com", "Amount Due" => "15.50", "Status" => "Open" },
      { "Email" => "nobody@example.com", "Amount Due" => "99.00" }, # error, excluded
    ]
    s = preview(rows).preview[:summary]
    assert_equal 2550, s[:total_amount_due_cents]
    assert_equal 1, s[:errors]
  end
end
