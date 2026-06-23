require "rails_helper"

RSpec.describe Billing::Invoices::Refunds::Save do
  let(:operator) { create(:operator) }
  let(:location) { create(:location, operator: operator) }
  let(:user)     { create(:user, operator: operator) }

  before { allow(Honeybadger).to receive(:notify) }

  # The refund is committed the instant invoice.cancel returns true. A failure
  # in the best-effort feed/search side effect must NOT report the refund as
  # failed (that's how a committed refund showed the operator a 502). See ADR 0014.
  it "still succeeds when the post-refund feed item raises an OpenSearch error" do
    invoice = double("invoice", cancel: true, billable: user, location: location, id: 123)
    allow(FeedItemCreator).to receive(:create_feed_item)
      .and_raise(OpenSearch::Transport::Transport::Errors::BadGateway.new("[502] Bad Gateway"))

    result = described_class.call(invoice: invoice, operator: operator, location: location)

    expect(result).to be_a_success
  end

  it "creates the feed item on the happy path" do
    invoice = double("invoice", cancel: true, billable: user, location: location, id: 2)
    expect(FeedItemCreator).to receive(:create_feed_item)

    result = described_class.call(invoice: invoice, operator: operator, location: location)

    expect(result).to be_a_success
  end

  it "fails cleanly (no crash) when the invoice cannot be refunded" do
    invoice = double("invoice", cancel: false, billable: user, location: location, id: 3)

    result = described_class.call(invoice: invoice, operator: operator, location: location)

    expect(result).to be_a_failure
    expect(result.message).to match(/refund/i)
  end
end
