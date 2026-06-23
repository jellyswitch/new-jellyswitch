require "rails_helper"

RSpec.describe RefundableFactory do
  it "returns a NotRefundable null-object (never nil) when the invoice is neither voidable nor paid" do
    invoice = instance_double("Invoice", voidable?: false, paid?: false)

    refundable = described_class.for(invoice)

    expect(refundable).to be_a(Refundable::NotRefundable)
    expect(refundable.cancel).to be(false) # caller can safely .cancel; no crash
  end

  it "returns a RefundableInvoice for a paid invoice" do
    invoice = instance_double("Invoice", voidable?: false, paid?: true)
    expect(described_class.for(invoice)).to be_a(Refundable::RefundableInvoice)
  end

  it "returns a VoidableInvoice for a voidable invoice" do
    invoice = instance_double("Invoice", voidable?: true, paid?: false)
    expect(described_class.for(invoice)).to be_a(Refundable::VoidableInvoice)
  end
end
