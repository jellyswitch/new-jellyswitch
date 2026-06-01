require "rails_helper"

RSpec.describe UpdateOrganizationBilling, type: :interactor do
  # We're testing the orchestration: did the interactor call the right Stripe
  # path when the org.out_of_band flag flipped? Subscription / Plan / Stripe
  # objects are all stubbed to keep this fast (no DB, no Stripe).

  let(:stripe_sub_state) { { billing: nil, days_until_due: nil, saved: false } }
  let(:stripe_sub_double) do
    s = stripe_sub_state
    double("Stripe::Subscription").tap do |d|
      allow(d).to receive(:billing=) { |v| s[:billing] = v }
      allow(d).to receive(:days_until_due=) { |v| s[:days_until_due] = v }
      allow(d).to receive(:save) { s[:saved] = true }
    end
  end

  let(:subscription) do
    double("Subscription",
      id: 42,
      stripe_subscription_id: "sub_test123",
      stripe_subscription: stripe_sub_double,
    )
  end

  let(:subscriptions_active_scope) { [subscription] }
  let(:subscriptions_proxy) { double("subscriptions").tap { |p| allow(p).to receive(:active).and_return(subscriptions_active_scope) } }

  let(:organization) do
    double("Organization",
      id: 1429,
      subscriptions: subscriptions_proxy,
    )
  end

  describe "out_of_band → in-band transition (the Aimee Dalton / Wild & Well bug)" do
    let(:stripe_customer) do
      double("Stripe::Customer", id: "cus_test123", save: true).tap do |c|
        allow(c).to receive(:source=)
      end
    end

    before do
      allow(organization).to receive(:out_of_band?).and_return(true)
      allow(organization).to receive(:find_or_create_stripe_customer).and_return(stripe_customer)
      allow(organization).to receive(:stripe_customer_id=)
      allow(organization).to receive(:out_of_band=)
      allow(organization).to receive(:save).and_return(true)
    end

    it "syncs the existing Stripe subscription to charge_automatically" do
      UpdateOrganizationBilling.call(
        organization: organization,
        stripe_token: "tok_test",
        out_of_band: false,
      )

      expect(stripe_sub_state[:billing]).to eq("charge_automatically")
      expect(stripe_sub_state[:days_until_due]).to be_nil
      expect(stripe_sub_state[:saved]).to eq(true)
    end

    it "skips Stripe sync if the org was already in-band (no flip)" do
      allow(organization).to receive(:out_of_band?).and_return(false)

      UpdateOrganizationBilling.call(
        organization: organization,
        stripe_token: "tok_test",
        out_of_band: false,
      )

      expect(stripe_sub_state[:saved]).to eq(false)
    end
  end

  describe "in-band → out_of_band transition" do
    before do
      allow(organization).to receive(:out_of_band?).and_return(false)
      allow(organization).to receive(:update).with(out_of_band: true).and_return(true)
    end

    it "syncs the existing Stripe subscription to send_invoice with 30 days due" do
      UpdateOrganizationBilling.call(
        organization: organization,
        stripe_token: nil,
        out_of_band: true,
      )

      expect(stripe_sub_state[:billing]).to eq("send_invoice")
      expect(stripe_sub_state[:days_until_due]).to eq(30)
      expect(stripe_sub_state[:saved]).to eq(true)
    end
  end

  describe "no-op flip (out_of_band → out_of_band)" do
    before do
      allow(organization).to receive(:out_of_band?).and_return(true)
      allow(organization).to receive(:update).with(out_of_band: true).and_return(true)
    end

    it "does NOT touch any Stripe subscription" do
      UpdateOrganizationBilling.call(
        organization: organization,
        stripe_token: nil,
        out_of_band: true,
      )

      expect(stripe_sub_state[:saved]).to eq(false)
    end
  end

  describe "when subscription.stripe_subscription is nil (e.g. pending sub)" do
    before do
      allow(organization).to receive(:out_of_band?).and_return(false)
      allow(organization).to receive(:update).with(out_of_band: true).and_return(true)
      allow(subscription).to receive(:stripe_subscription).and_return(nil)
    end

    it "gracefully skips it" do
      expect {
        UpdateOrganizationBilling.call(
          organization: organization,
          stripe_token: nil,
          out_of_band: true,
        )
      }.not_to raise_error
    end
  end

  describe "when Stripe sub update raises" do
    before do
      allow(organization).to receive(:out_of_band?).and_return(false)
      allow(organization).to receive(:update).with(out_of_band: true).and_return(true)
      allow(stripe_sub_double).to receive(:save).and_raise(
        Stripe::APIError.new("connection blip"),
      )
    end

    it "swallows the error (best-effort) and reports to Honeybadger" do
      expect(Honeybadger).to receive(:notify) do |err, *rest, **kwargs|
        expect(err).to be_a(Stripe::StripeError)
        ctx = kwargs[:context] || rest.first&.dig(:context) || rest.first
        expect(ctx).to include(organization_id: 1429, target_billing: "send_invoice")
      end

      expect {
        UpdateOrganizationBilling.call(
          organization: organization,
          stripe_token: nil,
          out_of_band: true,
        )
      }.not_to raise_error
    end
  end
end
