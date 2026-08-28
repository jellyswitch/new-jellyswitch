require "rails_helper"

# Regression: a bundle-sourced entry pass (minted by burning a prepaid N-Pack
# on building entry) carries the full pack price in day_pass_type.amount_in_cents.
# Summing that per daily entry double-counts the one-time bundle purchase as
# recurring day-pass revenue in the digest. generate_digest must exclude those
# entries via `not_bundle_sourced`.
#
# Note: DailyActivityDigestJob#perform is currently disabled (no-op). These specs
# exercise the private `generate_digest` method directly so the bug fix is
# covered and will catch any regression if perform is re-enabled.
RSpec.describe DailyActivityDigestJob, type: :job do
  let(:operator) { create(:operator) }
  let(:location) { create(:location, operator: operator, name: "Zephyr Cove") }
  let(:admin)    { create(:user, operator: operator, role: "superadmin",
                                original_location: location, current_location: location) }

  let(:single_type) { create(:day_pass_type, operator: operator, location: location,
                                             name: "Single", amount_in_cents: 2_500) }
  let(:pack_type)   { create(:day_pass_type, operator: operator, location: location,
                                             name: "10-Pack", quantity: 10, amount_in_cents: 20_000) }

  let(:individual) { create(:user, operator: operator, original_location: location,
                                   current_location: location, name: "Individual Ida") }
  let(:bundler)    { create(:user, operator: operator, original_location: location,
                                   current_location: location, name: "Bundle Bob") }

  before do
    # Ensure admin exists (evaluated before day passes so superadmin is in DB)
    admin

    # A normally-purchased day pass for today → $25 of real revenue.
    create(:day_pass, user: individual, billable: individual, operator: operator,
                      location: location, day_pass_type: single_type, day: Date.current)

    # A 10-Pack bundle burned on entry today → mints a DayPass whose
    # day_pass_type.amount_in_cents is the full $200 pack price.
    DayPassBundle.create!(user: bundler, billable: bundler, operator: operator,
                          location: location, day_pass_type: pack_type,
                          quantity_purchased: 10, passes_remaining: 10,
                          purchased_at: Time.current)
    Billing::DayPassBundles::ConsumeOnEntry.call(user: bundler, location: location)
  end

  describe "#generate_digest (private)" do
    # generate_digest returns the FeedItem it creates (or nil if guards bail).
    # It wraps FeedItem.create! in ActsAsTenant.with_tenant, so capture it here
    # — querying FeedItem.last outside a tenant context would hit the tenant scope.
    subject(:feed_item) do
      described_class.new.send(:generate_digest, operator, location)
    end

    it "creates a feed item for today" do
      expect(subject).to be_present
    end

    # FeedItem#blob is JSONB — keys round-trip as strings, not symbols.
    it "counts both the individual pass and bundle entry as visits" do
      blob = subject.blob
      expect(blob["day_pass_count"]).to eq(2)
    end

    it "excludes the bundle entry's full pack price from day-pass revenue" do
      blob = subject.blob
      # Only the $25 individual pass should count — NOT the $200 pack price.
      # total_revenue_cents has no paid reservations today, so it equals the
      # day-pass contribution only.
      expect(blob["total_revenue_cents"]).to eq(2_500)
    end
  end
end
