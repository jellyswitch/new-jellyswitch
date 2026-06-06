require "test_helper"

class Officernd::DayPassColumnDetectorTest < ActiveSupport::TestCase
  test "detects typical day-pass headers" do
    m = Officernd::DayPassColumnDetector.detect(
      ["Email", "Pass Type", "Visit Date", "Complimentary", "Stripe Customer", "Charge ID"],
    )

    assert_equal "Email", m[:email]
    assert_equal "Pass Type", m[:day_pass_type]
    assert_equal "Visit Date", m[:day]
    assert_equal "Complimentary", m[:complimentary]
    assert_equal "Stripe Customer", m[:stripe_customer_id]
    assert_equal "Charge ID", m[:stripe_charge_id]
  end

  test "pass type is not stolen by the generic date matcher and vice versa" do
    m = Officernd::DayPassColumnDetector.detect(["Day Pass Type", "Day Pass Date"])
    assert_equal "Day Pass Type", m[:day_pass_type]
    assert_equal "Day Pass Date", m[:day]
  end

  test "omits fields with no matching header" do
    m = Officernd::DayPassColumnDetector.detect(["Email"])
    assert_equal "Email", m[:email]
    refute m.key?(:day_pass_type)
  end
end
