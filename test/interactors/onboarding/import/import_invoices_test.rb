require "test_helper"

class Onboarding::Import::ImportInvoicesTest < ActiveSupport::TestCase
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

  def import(rows, amount_format: :dollars)
    Onboarding::Import::ImportInvoices.call(
      location: @location, rows: rows, column_mapping: @cm, amount_format: amount_format,
    )
  end

  test "fails without a location" do
    assert Onboarding::Import::ImportInvoices.call(location: nil, rows: []).failure?
  end

  test "creates a historical invoice anchored to its stripe id, preserving date and amounts" do
    rows = [{ "Email" => "tim@jellyswitch.com", "Stripe Invoice" => "in_HIST1", "Invoice #" => "A-1",
              "Amount Due" => "$25.00", "Amount Paid" => "$25.00", "Status" => "Paid",
              "Date" => "2024-01-15" }]

    assert_difference -> { Invoice.count } => 1 do
      result = import(rows)
      assert result.success?, result.message
      assert_equal 1, result.report[:summary][:invoices_created]
    end

    inv = Invoice.find_by(stripe_invoice_id: "in_HIST1")
    assert_equal @member, inv.billable
    assert_equal 2500, inv.amount_due
    assert_equal 2500, inv.amount_paid
    assert_equal "paid", inv.status
    assert_equal @location.id, inv.location_id
    assert_equal 2024, inv.date.year
    assert_equal 2024, inv.created_at.year # back-dated to the invoice date
  end

  test "is idempotent — re-running updates instead of duplicating" do
    rows = [{ "Email" => "tim@jellyswitch.com", "Stripe Invoice" => "in_HIST2",
              "Amount Due" => "10.00", "Status" => "Open" }]
    import(rows)

    assert_no_difference -> { Invoice.count } do
      result = import(rows)
      assert_equal :updated, result.report[:rows].first[:action]
    end
  end

  test "does NOT grant retroactive credits" do
    before = @member.reload.credit_balance
    rows = [{ "Email" => "tim@jellyswitch.com", "Stripe Invoice" => "in_HIST3",
              "Amount Due" => "50.00", "Status" => "Paid" }]
    import(rows)
    assert_equal before, @member.reload.credit_balance
  end

  test "skips a row whose billable cannot be resolved" do
    rows = [{ "Email" => "nobody@example.com", "Amount Due" => "10.00" }]

    assert_no_difference -> { Invoice.count } do
      result = import(rows)
      assert_equal :skipped, result.report[:rows].first[:action]
      assert_equal 1, result.report[:summary][:skipped]
    end
  end

  test "skips a row with an unparseable amount" do
    rows = [{ "Email" => "tim@jellyswitch.com", "Stripe Invoice" => "in_BAD", "Amount Due" => "lots" }]

    assert_no_difference -> { Invoice.count } do
      result = import(rows)
      assert_equal :skipped, result.report[:rows].first[:action]
    end
  end

  test "respects the :cents amount format" do
    rows = [{ "Email" => "tim@jellyswitch.com", "Stripe Invoice" => "in_CENTS",
              "Amount Due" => "2500", "Status" => "Paid" }]
    import(rows, amount_format: :cents)
    assert_equal 2500, Invoice.find_by(stripe_invoice_id: "in_CENTS").amount_due
  end
end
