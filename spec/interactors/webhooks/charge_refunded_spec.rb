require "rails_helper"

RSpec.describe Webhooks::ChargeRefunded do
  let(:operator) { create(:operator, stripe_user_id: "acct_OP") }
  let(:location) { create(:location, operator: operator) }

  def charge_event(overrides = {})
    object = {
      object: "charge",
      id: "ch_1",
      payment_intent: nil,
      invoice: nil,
      amount_refunded: 1000,
      refunds: { object: "list", data: [{ object: "refund", id: "re_1", amount: 1000 }] },
    }.merge(overrides)

    Stripe::Event.construct_from(type: "charge.refunded", account: "acct_OP", data: { object: object })
  end

  def refund_event(type, overrides = {})
    object = {
      object: "refund",
      id: "re_1",
      charge: "ch_1",
      payment_intent: nil,
      amount: 1000,
      status: "succeeded",
    }.merge(overrides)

    Stripe::Event.construct_from(type: type, account: "acct_OP", data: { object: object })
  end

  describe "matching a PaymentIntent-backed invoice (charge.refunded)" do
    let!(:invoice) do
      create(:invoice, operator: operator, location: location, status: "paid",
             amount_due: 1000, stripe_payment_intent_id: "pi_1", stripe_invoice_id: nil)
    end

    it "reconciles the invoice to refunded with the refund id" do
      result = described_class.call(event: charge_event(payment_intent: "pi_1"))

      expect(result).to be_success
      expect(invoice.reload.status).to eq("refunded")
      expect(invoice.refunds.first.stripe_refund_id).to eq("re_1")
      expect(invoice.refund_amount_in_cents).to eq(1000)
    end
  end

  describe "matching a legacy Stripe-Invoice-backed invoice (charge.refunded)" do
    let!(:invoice) do
      create(:invoice, operator: operator, location: location, status: "paid",
             amount_due: 1000, stripe_invoice_id: "in_1", stripe_payment_intent_id: nil)
    end

    it "matches via the charge's invoice id and reconciles" do
      result = described_class.call(event: charge_event(invoice: "in_1"))

      expect(result).to be_success
      expect(invoice.reload.status).to eq("refunded")
      expect(invoice.refunds.first.stripe_refund_id).to eq("re_1")
    end
  end

  describe "idempotency across the events one refund fires" do
    let!(:invoice) do
      create(:invoice, operator: operator, location: location, status: "paid",
             amount_due: 1000, stripe_payment_intent_id: "pi_1")
    end

    it "does not duplicate the refund row when charge.refunded then refund.created arrive" do
      described_class.call(event: charge_event(payment_intent: "pi_1"))
      described_class.call(event: refund_event("refund.created", payment_intent: "pi_1"))
      described_class.call(event: refund_event("charge.refund.updated", payment_intent: "pi_1"))

      expect(invoice.reload.refunds.count).to eq(1)
      expect(invoice.refunds.first.stripe_refund_id).to eq("re_1")
    end
  end

  describe "when no local invoice matches" do
    it "succeeds (acknowledges) without raising" do
      result = described_class.call(event: charge_event(payment_intent: "pi_nope"))
      expect(result).to be_success
    end
  end

  describe "refund.created for a PI-backed invoice" do
    let!(:invoice) do
      create(:invoice, operator: operator, location: location, status: "paid",
             amount_due: 1000, stripe_payment_intent_id: "pi_1")
    end

    it "reconciles using the refund object's payment_intent" do
      result = described_class.call(event: refund_event("refund.created", payment_intent: "pi_1"))

      expect(result).to be_success
      expect(invoice.reload.status).to eq("refunded")
      expect(invoice.refunds.first.stripe_refund_id).to eq("re_1")
    end
  end
end
