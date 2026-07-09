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
end
