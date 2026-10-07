require "test_helper"

# Cards saved via SetupIntent or while paying a Stripe-hosted invoice exist only
# as PaymentMethods; the old sources-only checks reported "no card" for them
# (Tanya Wilson, group 1595, 2026-10-06).
class StripeCardLookupTest < ActiveSupport::TestCase
  Card = Struct.new(:last4)
  Source = Struct.new(:object, :last4)
  List = Struct.new(:data)

  def customer(sources: [], default_pm: nil, id: "cus_test")
    OpenStruct.new(
      id: id,
      sources: OpenStruct.new(data: sources).tap { |s| s.define_singleton_method(:[]) { |k| k == "data" ? sources : nil } },
      invoice_settings: OpenStruct.new(default_payment_method: default_pm),
    )
  end

  setup do
    @location = locations(:cowork_tahoe_location)
  end

  test "a legacy card source is used first, without calling PaymentMethods" do
    Stripe::PaymentMethod.expects(:retrieve).never
    Stripe::PaymentMethod.expects(:list).never

    assert_equal "1111", @location.first_card_for(customer(sources: [Source.new("card", "1111")])).last4
  end

  test "falls back to the customer's default PaymentMethod" do
    Stripe::PaymentMethod.expects(:retrieve).with("pm_default", anything)
                         .returns(OpenStruct.new(card: Card.new("0295")))

    assert_equal "0295", @location.first_card_for(customer(default_pm: "pm_default")).last4
  end

  test "falls back to any attached card PaymentMethod" do
    Stripe::PaymentMethod.expects(:list).with(has_entries(customer: "cus_test", type: "card"), anything)
                         .returns(List.new([OpenStruct.new(card: Card.new("4242"))]))

    assert_equal "4242", @location.first_card_for(customer).last4
  end

  test "no card anywhere is nil" do
    Stripe::PaymentMethod.stubs(:list).returns(List.new([]))

    assert_nil @location.first_card_for(customer)
    assert_nil @location.first_card_for(nil)
  end

  test "User#card_last_4_digits sees a PaymentMethod-only card" do
    user = users(:cowork_tahoe_member)
    user.stubs(:stripe_customer_for_location).returns(customer(default_pm: "pm_default"))
    Stripe::PaymentMethod.stubs(:retrieve).returns(OpenStruct.new(card: Card.new("0295")))

    assert_equal "0295", user.card_last_4_digits(@location)
  end

  test "Organization#card_added sees a PaymentMethod-only card" do
    org = organizations(:sierra_nevada_organization)
    org.stubs(:stripe_customer).returns(customer(default_pm: "pm_default"))
    org.stubs(:stripe_customer_for_location).returns(customer(default_pm: "pm_default"))
    Stripe::PaymentMethod.stubs(:retrieve).returns(OpenStruct.new(card: Card.new("0295")))

    assert org.card_added?
    assert_equal "0295", org.card_last_4_digits(@location)
  end

  test "Organization#card_added is false with no card and no customer" do
    org = organizations(:sierra_nevada_organization)
    org.stubs(:stripe_customer).returns(customer)
    Stripe::PaymentMethod.stubs(:list).returns(List.new([]))
    assert_not org.card_added?

    org.stubs(:stripe_customer).returns(nil)
    assert_not org.card_added?
  end
end
