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

  def stripe_snapshot(status:, amount_paid:)
    Stripe::Invoice.construct_from(
      id: invoice.stripe_invoice_id, status: status,
      amount_due: 9900, amount_paid: amount_paid
    )
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
end
