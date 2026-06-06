require "test_helper"

class Officernd::InvoiceColumnDetectorTest < ActiveSupport::TestCase
  test "detects typical invoice headers" do
    headers = ["Invoice #", "Stripe Invoice", "Stripe Customer", "Email",
               "Amount Due", "Amount Paid", "Status", "Date", "Due Date", "Description"]
    m = Officernd::InvoiceColumnDetector.detect(headers)

    assert_equal "Stripe Invoice", m[:stripe_invoice_id]
    assert_equal "Stripe Customer", m[:stripe_customer_id]
    assert_equal "Email", m[:email]
    assert_equal "Invoice #", m[:number]
    assert_equal "Amount Due", m[:amount_due]
    assert_equal "Amount Paid", m[:amount_paid]
    assert_equal "Status", m[:status]
    assert_equal "Date", m[:date]
    assert_equal "Due Date", m[:due_date]
    assert_equal "Description", m[:description]
  end

  test "amount due and amount paid do not collide on one header" do
    m = Officernd::InvoiceColumnDetector.detect(["Amount Due", "Amount Paid"])
    assert_equal "Amount Due", m[:amount_due]
    assert_equal "Amount Paid", m[:amount_paid]
    assert_not_equal m[:amount_due], m[:amount_paid]
  end

  test "due date is not stolen by the generic date matcher" do
    m = Officernd::InvoiceColumnDetector.detect(["Invoice Date", "Due Date"])
    assert_equal "Due Date", m[:due_date]
    assert_equal "Invoice Date", m[:date]
  end
end
