require "test_helper"

class Officernd::MoneyTest < ActiveSupport::TestCase
  test "parses dollar strings to cents by default" do
    assert_equal 2500, Officernd::Money.to_cents("25")
    assert_equal 2500, Officernd::Money.to_cents("25.00")
    assert_equal 123456, Officernd::Money.to_cents("$1,234.56")
    assert_equal 999, Officernd::Money.to_cents("9.99")
  end

  test "parses integer cents when format is :cents" do
    assert_equal 25, Officernd::Money.to_cents("25", format: :cents)
    assert_equal 2500, Officernd::Money.to_cents("2500", format: :cents)
  end

  test "handles negatives including accounting parentheses" do
    assert_equal(-500, Officernd::Money.to_cents("-5.00"))
    assert_equal(-500, Officernd::Money.to_cents("(5.00)"))
  end

  test "returns nil for blank input" do
    assert_nil Officernd::Money.to_cents(nil)
    assert_nil Officernd::Money.to_cents("")
    assert_nil Officernd::Money.to_cents("   ")
  end

  test "rounds to the nearest cent" do
    assert_equal 1, Officernd::Money.to_cents("0.005")
    assert_equal 0, Officernd::Money.to_cents("0.004")
  end

  test "raises ParseError on non-numeric input" do
    assert_raises(Officernd::Money::ParseError) { Officernd::Money.to_cents("abc") }
    assert_raises(Officernd::Money::ParseError) { Officernd::Money.to_cents("12.3.4") }
  end
end
