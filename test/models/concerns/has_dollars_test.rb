require "test_helper"

class HasDollarsTest < ActiveSupport::TestCase
  # Lightweight test class — no DB, just attribute storage
  class Fake
    include ActiveModel::Model
    include ActiveModel::Attributes
    include HasDollars

    attribute :price_in_cents, :integer
    dollars :price
  end

  test "reads dollars from cents column" do
    fake = Fake.new(price_in_cents: 2599)
    assert_in_delta 25.99, fake.price, 0.0001
  end

  test "writes dollars to cents column" do
    fake = Fake.new
    fake.price = "40.99"
    assert_equal 4099, fake.price_in_cents
  end

  test "handles whole-dollar string" do
    fake = Fake.new
    fake.price = "25"
    assert_equal 2500, fake.price_in_cents
  end

  test "handles numeric input" do
    fake = Fake.new
    fake.price = 12.5
    assert_equal 1250, fake.price_in_cents
  end

  test "blank input clears cents to nil" do
    fake = Fake.new(price_in_cents: 500)
    fake.price = ""
    assert_nil fake.price_in_cents
  end

  test "nil input clears cents to nil" do
    fake = Fake.new(price_in_cents: 500)
    fake.price = nil
    assert_nil fake.price_in_cents
  end

  test "whitespace-only string clears cents to nil" do
    fake = Fake.new(price_in_cents: 500)
    fake.price = "   "
    assert_nil fake.price_in_cents
  end

  test "nil cents reads as nil dollars" do
    fake = Fake.new(price_in_cents: nil)
    assert_nil fake.price
  end

  test "accepts multiple field names" do
    klass = Class.new do
      include ActiveModel::Model
      include ActiveModel::Attributes
      include HasDollars

      attribute :a_in_cents, :integer
      attribute :b_in_cents, :integer
      dollars :a, :b
    end

    obj = klass.new(a_in_cents: 100, b_in_cents: 200)
    assert_equal 1.0, obj.a
    assert_equal 2.0, obj.b
  end
end
