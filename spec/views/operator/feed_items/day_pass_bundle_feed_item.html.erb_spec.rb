require "rails_helper"

RSpec.describe "operator/feed_items/_day_pass_bundle_feed_item", type: :view do
  let(:day_pass_type) do
    instance_double("DayPassType", name: "5-Pack", free?: false, amount_in_cents: 20_000)
  end
  let(:bundle) do
    instance_double("DayPassBundle", day_pass_type: day_pass_type,
                                     quantity_purchased: 5, passes_remaining: 5,
                                     expires_at: nil)
  end
  let(:feed_item) { instance_double("FeedItem", day_pass_bundle: bundle) }

  it "renders pack size, type, the pack price as amount, and a perpetual expiry" do
    render partial: "operator/feed_items/day_pass_bundle_feed_item", locals: { feed_item: feed_item }

    expect(rendered).to include("5-Pack")
    expect(rendered).to include("$200.00")   # 20_000 cents, flat pack price
    expect(rendered).to include("Never")     # no expires_at
    expect(rendered).not_to include("Passes remaining") # live balance stays off the event log
  end

  it "shows an expiry date when the pack expires" do
    allow(bundle).to receive(:expires_at).and_return(Time.zone.local(2026, 9, 1))
    render partial: "operator/feed_items/day_pass_bundle_feed_item", locals: { feed_item: feed_item }

    expect(rendered).to include("September")
    expect(rendered).to include("2026")
  end
end
