require "rails_helper"
require Rails.root.join("db/migrate/20260709140000_backfill_last_purchase_interest_tags.rb")

RSpec.describe BackfillLastPurchaseInterestTags do
  let(:operator) { create(:operator) }
  let(:location) { create(:location, operator: operator) }

  it "seeds last_purchase tags for existing purchases, idempotently and staff-safe" do
    buyer = create(:user, operator: operator, original_location: location)
    create(:day_pass, user: buyer, billable: buyer, operator: operator, location: location, day: 30.days.ago.to_date)
    create(:day_pass_bundle, user: buyer, operator: operator, location: location)
    create(:subscription, subscribable: buyer, billable: buyer, plan: create(:plan, operator: operator))
    create(:reservation, user: buyer, room: create(:room, operator: operator, location: location, rentable: true, hourly_rate_in_cents: 2000))

    # A staff tag that must survive the backfill.
    staffed = create(:user, operator: operator, original_location: location)
    InterestTag.record(user: staffed, product: "day_pass", source: "staff", added_by: staffed)
    create(:day_pass, user: staffed, billable: staffed, operator: operator, location: location, day: Date.current)

    # Simulate pre-feature state: wipe the tags the live hooks just created so the
    # backfill has work to do. (The staff tag isn't a last_purchase tag.)
    InterestTag.where(source: "last_purchase").delete_all

    expect { described_class.new.up }.to change { InterestTag.where(source: "last_purchase").count }.from(0)

    expect(buyer.interest_tags.for_product("day_pass").first&.source).to eq("last_purchase")
    expect(buyer.interest_tags.for_product("membership").first&.source).to eq("last_purchase")
    expect(buyer.interest_tags.for_product("meeting_room").first&.source).to eq("last_purchase")
    expect(buyer.interest_tags.for_product("day_pass").first.last_purchased_at).to be_present

    # Staff tag untouched.
    expect(staffed.interest_tags.for_product("day_pass").first.source).to eq("staff")

    # Re-running is a no-op (upsert, unique index).
    expect { described_class.new.up }.not_to change { InterestTag.count }
  end

  it "records the NEWEST day_pass purchase time even though bundles are backfilled after activities" do
    # A buyer whose most-recent day_pass purchase is a single pass (Jun), with an
    # OLDER bundle (Jan). The backfill replays Activities first, then bundles — so a
    # non-monotonic stamp would let the older bundle clobber the newer date.
    buyer = create(:user, operator: operator, original_location: location)
    newest = Time.current.change(usec: 0) - 10.days
    oldest = newest - 150.days

    pass = create(:day_pass, user: buyer, billable: buyer, operator: operator, location: location, day: newest.to_date)
    # The after_create hook already logged a day_pass Activity — date it to `newest`.
    Activity.where(subject: pass).update_all(occurred_at: newest)
    bundle = create(:day_pass_bundle, user: buyer, operator: operator, location: location)
    bundle.update_column(:created_at, oldest)

    InterestTag.where(source: "last_purchase").delete_all

    described_class.new.up

    tag = buyer.interest_tags.for_product("day_pass").first
    expect(tag.last_purchased_at).to be_within(1.second).of(newest)
  end
end
