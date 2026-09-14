require "test_helper"

class Billing::Invoices::AddCreditsToSubscribableTest < ActiveSupport::TestCase
  test "succeeds without touching Stripe when the invoice has no location and no Stripe invoice is supplied" do
    invoice = invoices(:member_invoice)
    invoice.update_columns(location_id: nil)

    Stripe::Invoice.expects(:retrieve).never

    result = Billing::Invoices::AddCreditsToSubscribable.call(invoice: invoice)

    assert result.success?
  end

  test "uses the supplied Stripe invoice instead of re-fetching it" do
    invoice = invoices(:member_invoice)
    line = OpenStruct.new(subscription: "sub_does_not_exist")
    stripe_invoice = OpenStruct.new(lines: OpenStruct.new(count: 1, first: line))

    Stripe::Invoice.expects(:retrieve).never

    result = Billing::Invoices::AddCreditsToSubscribable.call(invoice: invoice, stripe_invoice: stripe_invoice)

    assert result.success?
  end

  test "ignores lines that are not tied to a subscription" do
    invoice = invoices(:member_invoice)
    line = OpenStruct.new(subscription: nil)
    stripe_invoice = OpenStruct.new(lines: OpenStruct.new(count: 1, first: line))

    Subscription.expects(:find_by).never

    result = Billing::Invoices::AddCreditsToSubscribable.call(invoice: invoice, stripe_invoice: stripe_invoice)

    assert result.success?
  end
end
