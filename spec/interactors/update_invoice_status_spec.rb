require "rails_helper"

RSpec.describe UpdateInvoiceStatus do
  let(:operator) { create(:operator) }
  let(:location) { create(:location, operator: operator) }
  let(:user) { create(:user, operator: operator, current_location: location) }
  let(:invoice) do
    create(:invoice, operator: operator, location: location, billable: user,
                     amount_due: 9900, amount_paid: 9900, status: "paid",
                     stripe_invoice_id: "in_REPLAY_TEST")
  end

  def stripe_snapshot(status:, amount_paid:, **overrides)
    Stripe::Invoice.construct_from({
      id: invoice.stripe_invoice_id, status: status,
      amount_due: 9900, amount_paid: amount_paid
    }.merge(overrides))
  end

  it "ignores a stale 'open' snapshot on a settled invoice (Stripe replay / out-of-order delivery)" do
    # A redelivered invoice.payment_failed carries the frozen at-failure-time
    # snapshot (open, amount_paid 0). It must not regress a paid invoice —
    # that would strand it as owed forever AND re-arm the payment-failed push.
    result = described_class.call(stripe_invoice: stripe_snapshot(status: "open", amount_paid: 0))

    expect(result).to be_success
    expect(invoice.reload.status).to eq("paid")
    expect(invoice.amount_paid).to eq(9900)
  end

  it "still applies genuine forward transitions" do
    invoice.update!(status: "open", amount_paid: 0)

    described_class.call(stripe_invoice: stripe_snapshot(status: "void", amount_paid: 0))

    expect(invoice.reload.status).to eq("void")
  end

  it "syncs the money fields from the snapshot" do
    invoice.update!(status: "draft", amount_due: 0, amount_paid: 0)

    result = described_class.call(
      stripe_invoice: stripe_snapshot(status: "open", amount_paid: 0, amount_due: 2500)
    )

    expect(result).to be_success
    expect(invoice.reload.status).to eq("open")
    expect(invoice.amount_due).to eq(2500)
  end

  describe "when no local invoice matches" do
    it "fails with a message naming the Stripe invoice" do
      result = described_class.call(
        stripe_invoice: stripe_snapshot(status: "open", amount_paid: 0, id: "in_missing")
      )

      expect(result).to be_failure
      expect(result.message).to include("in_missing")
    end
  end

  describe "when the invoice fails to save" do
    # Regression: the fail! message interpolated a bare `number`, which is
    # undefined on the interactor — save failures raised NameError instead of
    # failing cleanly, and the webhook's rescue masked the real errors.
    it "fails cleanly with the invoice number and validation errors instead of raising" do
      invoice.update!(status: "draft", number: "INV-123")
      allow(Invoice).to receive(:find_by)
        .with(stripe_invoice_id: invoice.stripe_invoice_id).and_return(invoice)
      allow(invoice).to receive(:save) do
        invoice.errors.add(:amount_due, "is not a number")
        false
      end

      result = nil
      expect {
        result = described_class.call(stripe_invoice: stripe_snapshot(status: "open", amount_paid: 0))
      }.not_to raise_error

      expect(result).to be_failure
      expect(result.message).to include("INV-123")
      expect(result.message).to include("open")
      expect(result.message).to include("Amount due is not a number")
    end
  end
end
