require "rails_helper"

RSpec.describe InterestTag, type: :model do
  let(:operator) { create(:operator) }
  let(:location) { create(:location, operator: operator) }
  let(:user)     { create(:user, operator: operator, original_location: location) }
  let(:staffer)  { create(:user, operator: operator, role: "superadmin", original_location: location) }

  def tag(attrs = {})
    InterestTag.new({ user: user, operator: operator, product: "office", source: "concierge" }.merge(attrs))
  end

  describe "validations" do
    it "is valid with a known product + source" do
      expect(tag).to be_valid
    end

    it "rejects an unknown product" do
      expect(tag(product: "parking")).not_to be_valid
    end

    it "accepts looked_at as a behavioral source (browsed without buying)" do
      expect(tag(source: "looked_at")).to be_valid
    end

    it "rejects an unknown source" do
      expect(tag(source: "vibes")).not_to be_valid
    end

    it "allows only one tag per (user, product)" do
      tag.save!
      dup = tag(source: "staff")
      expect(dup).not_to be_valid
      expect(dup.errors[:product]).to be_present
    end

    it "allows the same product for different users" do
      tag.save!
      other = create(:user, operator: operator, original_location: location)
      expect(tag(user: other)).to be_valid
    end

    it "allows different products for the same user" do
      tag.save!
      expect(tag(product: "membership", source: "last_purchase")).to be_valid
    end
  end

  describe "source scopes" do
    it "separates staff-set from behavioral tags" do
      behavioral = create(:user, operator: operator, original_location: location)
      InterestTag.create!(user: behavioral, operator: operator, product: "day_pass", source: "last_purchase")
      InterestTag.create!(user: user, operator: operator, product: "office", source: "staff", added_by: staffer)

      expect(InterestTag.staff_set.pluck(:product)).to eq(["office"])
      expect(InterestTag.behavioral.pluck(:product)).to eq(["day_pass"])
    end

    it "#staff_set? reflects the source" do
      expect(tag(source: "staff").staff_set?).to be true
      expect(tag(source: "concierge").staff_set?).to be false
    end
  end

  describe "associations" do
    it "is reachable via User#interest_tags and records who added it" do
      t = InterestTag.create!(user: user, operator: operator, product: "office", source: "staff", added_by: staffer)
      expect(user.interest_tags).to include(t)
      expect(t.added_by).to eq(staffer)
    end
  end

  describe ".record (upsert)" do
    it "creates a tag scoped to the user's operator" do
      t = InterestTag.record(user: user, product: "office", source: "concierge")
      expect(t).to be_persisted
      expect(t.operator).to eq(operator)
    end

    it "updates the existing tag on a repeat signal (no duplicate)" do
      InterestTag.record(user: user, product: "office", source: "looked_at")
      InterestTag.record(user: user, product: "office", source: "concierge")
      tags = InterestTag.where(user_id: user.id, product: "office")
      expect(tags.count).to eq(1)
      expect(tags.first.source).to eq("concierge")
    end

    it "does NOT let a behavioral signal overwrite a staff-set tag (sticky)" do
      InterestTag.record(user: user, product: "office", source: "staff", added_by: staffer)
      InterestTag.record(user: user, product: "office", source: "concierge")
      expect(InterestTag.find_by(user_id: user.id, product: "office").source).to eq("staff")
    end

    it "lets a staff edit win over a behavioral tag" do
      InterestTag.record(user: user, product: "office", source: "concierge")
      InterestTag.record(user: user, product: "office", source: "staff", added_by: staffer)
      tag = InterestTag.find_by(user_id: user.id, product: "office")
      expect(tag.source).to eq("staff")
      expect(tag.added_by).to eq(staffer)
    end

    it "ignores an unknown product or source" do
      expect(InterestTag.record(user: user, product: "parking", source: "staff")).to be_nil
      expect(InterestTag.record(user: user, product: "office", source: "vibes")).to be_nil
    end
  end

  describe ".record_from_concierge_intent" do
    it "maps office -> office and conference_room -> meeting_room" do
      InterestTag.record_from_concierge_intent(user, "office")
      other = create(:user, operator: operator, original_location: location)
      InterestTag.record_from_concierge_intent(other, "conference_room")
      expect(user.interest_tags.pluck(:product, :source)).to eq([["office", "concierge"]])
      expect(other.interest_tags.pluck(:product)).to eq(["meeting_room"])
    end

    it "ignores an intent that maps to no product" do
      expect(InterestTag.record_from_concierge_intent(user, "just_a_question")).to be_nil
      expect(user.interest_tags).to be_empty
    end
  end
end
