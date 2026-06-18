require "rails_helper"

# Event-fired bundle lifecycle emails enqueued from the burn path:
#   - review (follow_up): on the holder's FIRST entry burn
#   - replenishment: when the LAST pass is burned (passes_remaining -> 0)
RSpec.describe DayPassBundle, "email triggers on burn", type: :model do
  let(:operator)  { create(:operator) }
  let(:location)  { create(:location, operator: operator) }
  let(:user)      { create(:user, operator: operator, current_location: location) }
  let(:pack_type) { create(:day_pass_type, operator: operator, location: location, quantity: 5) }
  let(:bundle) do
    create(:day_pass_bundle, user: user, day_pass_type: pack_type, operator: operator,
                             location: location, quantity_purchased: 5, passes_remaining: 5)
  end

  def review_job
    have_enqueued_job(SendProductEmailJob)
      .with("DayPassBundle", bundle.id, operator.id, "day_pass_bundle", "follow_up", user.id)
  end

  def any_review_job
    have_enqueued_job(SendProductEmailJob).with(anything, anything, anything, anything, "follow_up", anything)
  end

  def any_replenishment_job
    have_enqueued_job(SendProductEmailJob).with(anything, anything, anything, anything, "replenishment", anything)
  end

  describe "review email (first entry)" do
    it "enqueues the review on the first entry burn" do
      expect { bundle.burn!(kind: :entry, performed_by: user) }.to review_job
    end

    it "does not enqueue the review on a later entry burn" do
      bundle.burn!(kind: :entry, performed_by: user)
      expect { bundle.burn!(kind: :entry, performed_by: user) }.not_to any_review_job
    end

    it "does not enqueue the review on a guest burn" do
      expect {
        bundle.burn!(kind: :guest, performed_by: user, guest_name: "Pat Guest")
      }.not_to any_review_job
    end
  end

  describe "replenishment email (zero balance)" do
    it "enqueues replenishment when the final pass is burned" do
      bundle.update!(passes_remaining: 1)
      expect { bundle.burn!(kind: :entry, performed_by: user) }.to(
        have_enqueued_job(SendProductEmailJob)
          .with("DayPassBundle", bundle.id, operator.id, "day_pass_bundle", "replenishment", user.id)
      )
    end

    it "does not enqueue replenishment while passes remain" do
      bundle.update!(passes_remaining: 3)
      expect { bundle.burn!(kind: :entry, performed_by: user) }.not_to any_replenishment_job
    end

    it "enqueues replenishment when the pack is emptied by a guest burn too" do
      bundle.update!(passes_remaining: 1)
      expect {
        bundle.burn!(kind: :guest, performed_by: user, guest_name: "Pat Guest")
      }.to any_replenishment_job
    end
  end
end
