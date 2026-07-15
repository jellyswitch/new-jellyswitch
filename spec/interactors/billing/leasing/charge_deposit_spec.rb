require "rails_helper"

RSpec.describe Billing::Leasing::ChargeDeposit, type: :interactor do
  let(:location) do
    double("location", stripe_user_id: "acct_test_123", stripe_secret_key: "sk_test_regression")
  end
  let(:office) { double("office", name: "Suite 200") }
  # Payer responds to BOTH; the location-scoped id is the one the subscription
  # actually bills, so the deposit must use it (not the plain column).
  let(:payer) do
    double("payer", stripe_customer_id_for_location: "cus_location_scoped", stripe_customer_id: "cus_plain")
  end
  let(:subscription) { double("subscription", billable: payer, subscribable: payer) }
  let(:office_lease) do
    double("office_lease", id: 4242, deposit_amount_in_cents: 50_000, deposit_invoiced_at: nil,
                           subscription: subscription, location: location, office: office)
  end

  before do
    allow(office_lease).to receive(:update!)
    allow(Stripe::InvoiceItem).to receive(:create)
    allow(Stripe::Invoice).to receive(:create).and_return(double("inv", id: "in_test_123"))
    allow(Stripe::Invoice).to receive(:finalize_invoice)
  end

  def run
    described_class.call(office_lease: office_lease, operator: double("operator"))
  end

  # Regression: every Stripe call must pass api_key explicitly (this app never
  # sets Stripe.api_key globally). Missing it silently failed the deposit.
  it "passes api_key (and stripe_account) on every Stripe call" do
    captured = []
    allow(Stripe::InvoiceItem).to receive(:create) { |_p, opts| captured << opts }
    allow(Stripe::Invoice).to receive(:create) { |_p, opts| captured << opts; double(id: "in_x") }
    allow(Stripe::Invoice).to receive(:finalize_invoice) { |_i, _p, opts| captured << opts }

    run
    expect(captured).not_to be_empty
    captured.each do |opts|
      expect(opts[:api_key]).to eq("sk_test_regression")
      expect(opts[:stripe_account]).to eq("acct_test_123")
    end
  end

  it "charges the LOCATION-SCOPED customer, not the plain stripe_customer_id" do
    expect(Stripe::InvoiceItem).to receive(:create)
      .with(hash_including(customer: "cus_location_scoped"), anything)
    run
  end

  it "stamps deposit_invoiced_at on success" do
    expect(office_lease).to receive(:update!).with(hash_including(:deposit_invoiced_at))
    run
  end

  it "passes a per-lease idempotency key so the recovery action can't double-charge" do
    keys = []
    allow(Stripe::InvoiceItem).to receive(:create) { |_p, opts| keys << opts[:idempotency_key] }
    allow(Stripe::Invoice).to receive(:create) { |_p, opts| keys << opts[:idempotency_key]; double(id: "in_x") }
    run
    expect(keys).to include("deposit-item-4242", "deposit-invoice-4242")
  end

  it "deletes the pending item when invoice creation fails (no orphan swept into the next invoice)" do
    allow(Stripe::InvoiceItem).to receive(:create).and_return(double(id: "ii_orphan"))
    allow(Stripe::Invoice).to receive(:create).and_raise(Stripe::StripeError.new("boom"))
    expect(Stripe::InvoiceItem).to receive(:delete).with("ii_orphan", anything)
    expect(office_lease).not_to receive(:update!) # never stamped on failure
    run # ChargeDeposit swallows the re-raise via its outer rescue
  end

  it "is idempotent — skips entirely when the deposit was already invoiced" do
    allow(office_lease).to receive(:deposit_invoiced_at).and_return(1.day.ago)
    expect(Stripe::InvoiceItem).not_to receive(:create)
    expect(office_lease).not_to receive(:update!)
    run
  end

  it "does nothing when there is no deposit" do
    allow(office_lease).to receive(:deposit_amount_in_cents).and_return(0)
    expect(Stripe::InvoiceItem).not_to receive(:create)
    run
  end
end
