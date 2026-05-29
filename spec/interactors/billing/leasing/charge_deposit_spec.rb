require "rails_helper"

RSpec.describe Billing::Leasing::ChargeDeposit, type: :interactor do
  # Regression for the production Stripe::AuthenticationError "No API key
  # provided" in operator/office_leases#create. This app NEVER sets
  # Stripe.api_key globally — every Stripe call must pass api_key explicitly.
  # ChargeDeposit's deposit calls passed only stripe_account, so the deposit
  # invoice silently failed (the error is rescued) and was never charged.
  let(:location) do
    double("location", stripe_user_id: "acct_test_123", stripe_secret_key: "sk_test_regression")
  end
  let(:office)       { double("office", name: "Suite 200") }
  let(:subscribable) { double("subscribable", stripe_customer_id: "cus_test_123") }
  let(:subscription) { double("subscription", subscribable: subscribable) }
  let(:office_lease) do
    double(
      "office_lease",
      deposit_amount_in_cents: 50_000,
      subscription: subscription,
      location: location,
      office: office,
    )
  end

  it "passes api_key (and stripe_account) on every Stripe call" do
    captured = []
    invoice  = double("stripe_invoice", id: "in_test_123")

    allow(Stripe::InvoiceItem).to receive(:create) { |_params, opts| captured << opts }
    allow(Stripe::Invoice).to receive(:create) { |_params, opts| captured << opts; invoice }
    allow(Stripe::Invoice).to receive(:finalize_invoice) { |_id, _params, opts| captured << opts }

    Billing::Leasing::ChargeDeposit.call(office_lease: office_lease, operator: double("operator"))

    expect(captured).not_to be_empty
    captured.each do |opts|
      expect(opts[:api_key]).to eq("sk_test_regression")
      expect(opts[:stripe_account]).to eq("acct_test_123")
    end
  end
end
