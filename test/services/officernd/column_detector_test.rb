require "test_helper"

class Officernd::ColumnDetectorTest < ActiveSupport::TestCase
  test "detects common headers" do
    headers = ["Full Name", "Email Address", "Phone", "Stripe Customer", "Membership", "Status"]
    mapping = Officernd::ColumnDetector.detect(headers)

    assert_equal "Full Name", mapping[:name]
    assert_equal "Email Address", mapping[:email]
    assert_equal "Phone", mapping[:phone]
    assert_equal "Stripe Customer", mapping[:stripe_customer_id]
    assert_equal "Membership", mapping[:membership]
    assert_equal "Status", mapping[:status]
  end

  test "company name does not get stolen by the generic name matcher" do
    mapping = Officernd::ColumnDetector.detect(["Company Name", "Contact Name"])

    assert_equal "Company Name", mapping[:company]
    assert_equal "Contact Name", mapping[:name]
  end

  test "is case insensitive and ignores blank headers" do
    mapping = Officernd::ColumnDetector.detect(["E-MAIL", "", "  ", "name"])

    assert_equal "E-MAIL", mapping[:email]
    assert_equal "name", mapping[:name]
  end

  test "omits canonical fields with no matching header" do
    mapping = Officernd::ColumnDetector.detect(["Email"])

    assert_equal "Email", mapping[:email]
    assert_nil mapping[:phone]
    refute mapping.key?(:company)
  end

  test "maps a single header to at most one field" do
    mapping = Officernd::ColumnDetector.detect(["Email"])

    assert_equal 1, mapping.values.length
    assert_equal mapping.values, mapping.values.uniq
  end
end
