require "rails_helper"

# Behavioral interest seeding (ADR 0022): purchases seed a `last_purchase`
# InterestTag per product, so the audience lists fill up from real behavior.
RSpec.describe "Behavioral interest seeding (last_purchase)", type: :model do
  let(:operator) { create(:operator) }
  let(:location) { create(:location, operator: operator) }
  let(:user)     { create(:user, operator: operator, original_location: location) }

  def tag_for(u, product)
    u.interest_tags.for_product(product).first
  end

  describe "DayPass" do
    it "seeds a day_pass last_purchase tag (with a purchase timestamp) on a real purchase" do
      create(:day_pass, user: user, billable: user, operator: operator, location: location, day: Date.current)
      t = tag_for(user, "day_pass")
      expect(t&.source).to eq("last_purchase")
      expect(t.last_purchased_at).to be_present
    end

    it "does NOT seed for an imported day pass (redemption / burn / import)" do
      create(:day_pass, user: user, billable: user, operator: operator, location: location, day: Date.current, imported: true)
      expect(tag_for(user, "day_pass")).to be_nil
    end
  end

  describe "DayPassBundle" do
    it "seeds a day_pass tag on purchase" do
      create(:day_pass_bundle, user: user, operator: operator, location: location)
      expect(tag_for(user, "day_pass")&.source).to eq("last_purchase")
    end
  end

  describe "Subscription (membership)" do
    it "seeds membership for an individual non-lease subscription" do
      create(:subscription, subscribable: user, billable: user, plan: create(:plan, operator: operator, plan_type: "individual"))
      expect(tag_for(user, "membership")&.source).to eq("last_purchase")
    end

    it "does NOT seed membership for an office-lease subscription" do
      create(:subscription, subscribable: user, billable: user, plan: create(:plan, operator: operator, plan_type: "lease"))
      expect(tag_for(user, "membership")).to be_nil
    end

    it "does NOT seed for an organization subscription (subscribable isn't a User)" do
      org = create(:organization, operator: operator)
      create(:subscription, subscribable: org, subscribable_type: "Organization",
                            billable: org, billable_type: "Organization", plan: create(:plan, operator: operator))
      expect(user.interest_tags).to be_empty
    end
  end

  describe "Reservation (paid meeting room)" do
    def paid_room
      create(:room, operator: operator, location: location, rentable: true, hourly_rate_in_cents: 2000)
    end

    it "seeds meeting_room for a paid-room booking" do
      create(:reservation, user: user, room: paid_room)
      expect(tag_for(user, "meeting_room")&.source).to eq("last_purchase")
    end

    it "does NOT seed for a free room" do
      create(:reservation, user: user, room: create(:room, operator: operator, location: location, rentable: true, hourly_rate_in_cents: 0))
      expect(tag_for(user, "meeting_room")).to be_nil
    end

    it "seeds for a member booking a paid room even when reservation.paid is false (exempt)" do
      create(:reservation, user: user, room: paid_room, paid: false)
      expect(tag_for(user, "meeting_room")&.source).to eq("last_purchase")
    end
  end

  describe "sticky staff tag" do
    it "a purchase does not overwrite a staff-set tag" do
      InterestTag.record(user: user, product: "day_pass", source: "staff", added_by: user)
      create(:day_pass, user: user, billable: user, operator: operator, location: location, day: Date.current)
      t = tag_for(user, "day_pass")
      expect(t.source).to eq("staff")
      expect(t.last_purchased_at).to be_nil # staff-sticky no-op'd the purchase write
    end
  end

  describe "most-recent purchase" do
    it "is the interest tag with the latest last_purchased_at" do
      create(:day_pass, user: user, billable: user, operator: operator, location: location, day: Date.current)
      tag_for(user, "day_pass").update_column(:last_purchased_at, 10.days.ago)
      create(:subscription, subscribable: user, billable: user, plan: create(:plan, operator: operator))
      tag_for(user, "membership").update_column(:last_purchased_at, 1.day.ago)

      recent = user.interest_tags.purchased.order(last_purchased_at: :desc).first
      expect(recent.product).to eq("membership")
    end
  end

  describe "office non-interaction" do
    it "signing an office lease leaves NO office (culled) and NO membership tag (lease plan)" do
      sub = create(:subscription, subscribable: user, billable: user, plan: create(:plan, operator: operator, plan_type: "lease"))
      create(:office_lease, organization: nil, user: user, operator: operator, location: location,
                            office: create(:office, operator: operator, location: location), subscription: sub)

      expect(user.interest_tags.for_product("office")).to be_empty
      expect(user.interest_tags.for_product("membership")).to be_empty
    end
  end
end
