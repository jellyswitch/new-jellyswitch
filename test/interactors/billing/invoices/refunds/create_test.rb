require "test_helper"

# Voiding an invoice whose Stripe-side object lives on a different account
# used to abort with a raw "No such invoice" flash, leaving the local invoice
# open forever. That happens for real when an operator reconnects Stripe:
# invoices created before the switch are orphaned on the old account (Tahoe
# Longhouse, 2026-07-17). The Stripe object is unreachable, so the void must
# still resolve local bookkeeping; genuine Stripe failures must still raise.
class Billing::Invoices::Refunds::CreateTest < ActiveSupport::TestCase
  setup do
    # CI doesn't set STRIPE_TEST_SECRET_KEY (local .env does), and a nil
    # api_key makes the Stripe client raise TypeError before WebMock can
    # match — stub the key so these tests behave the same everywhere.
    Location.any_instance.stubs(:stripe_secret_key).returns("sk_test_foobar")

    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
    @invoice = Invoice.create!(
      billable: users(:cowork_tahoe_member),
      operator: @operator,
      location: @location,
      amount_due: 5000,
      amount_paid: 0,
      status: "open",
      stripe_invoice_id: "in_orphaned123",
    )
  end

  def void_invoice!
    Billing::Invoices::Refunds::Create.call(
      operator: @operator,
      invoice: RefundableFactory.for(@invoice),
      location: @location,
    )
  end

  def stub_stripe_invoice_retrieve(status:, body:)
    stub_request(:get, "https://api.stripe.com/v1/invoices/in_orphaned123")
      .to_return(status: status, body: body.to_json)
  end

  test "voids the local invoice when the Stripe invoice is missing (account reconnect orphan)" do
    stub_stripe_invoice_retrieve(
      status: 404,
      body: {
        error: {
          type: "invalid_request_error",
          code: "resource_missing",
          param: "id",
          message: "No such invoice: 'in_orphaned123'",
        },
      },
    )
    Honeybadger.expects(:notify).never

    result = void_invoice!

    assert result.success?
    assert_equal "void", @invoice.reload.status
  end

  test "a genuine Stripe failure still raises and leaves the invoice open" do
    stub_stripe_invoice_retrieve(
      status: 400,
      body: {
        error: {
          type: "invalid_request_error",
          message: "You cannot void invoices in this state.",
        },
      },
    )

    assert_raises(Stripe::InvalidRequestError) { void_invoice! }
    assert_equal "open", @invoice.reload.status
  end

  test "voids on Stripe and locally when the Stripe invoice is reachable" do
    stub_stripe_invoice_retrieve(
      status: 200,
      body: { id: "in_orphaned123", object: "invoice", status: "open" },
    )
    void_stub = stub_request(:post, "https://api.stripe.com/v1/invoices/in_orphaned123/void")
      .to_return(status: 200, body: { id: "in_orphaned123", object: "invoice", status: "void" }.to_json)

    result = void_invoice!

    assert result.success?
    assert_requested void_stub
    assert_equal "void", @invoice.reload.status
  end
end
