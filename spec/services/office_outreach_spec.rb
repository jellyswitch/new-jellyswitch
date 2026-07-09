require "rails_helper"

RSpec.describe OfficeOutreach do
  let(:operator) { create(:operator) }
  let(:location) { create(:location, operator: operator) }
  let(:user)     { create(:user, operator: operator, original_location: location) }
  let(:staffer)  { create(:user, operator: operator, role: "admin", original_location: location) }
  let(:office)   { create(:office, operator: operator, location: location, name: "Pipkin Suite") }

  describe ".offer! / .decline!" do
    it "logs an office_offered Activity against the office, crediting the staffer" do
      activity = OfficeOutreach.offer!(user: user, office: office, added_by: staffer)

      expect(activity.kind).to eq("office_offered")
      expect(activity.user).to eq(user)
      expect(activity.operator).to eq(operator)
      expect(activity.subject).to eq(office)
      expect(activity.payload["office_name"]).to eq("Pipkin Suite")
      expect(activity.payload["added_by_id"]).to eq(staffer.id)
    end

    it "logs an office_declined Activity" do
      activity = OfficeOutreach.decline!(user: user, office: office, added_by: staffer)
      expect(activity.kind).to eq("office_declined")
      expect(user.activities.where(kind: "office_declined")).to exist
    end
  end

  describe ".status_for" do
    it "is :not_contacted with no outreach and no lease" do
      expect(OfficeOutreach.status_for(user)).to eq(:not_contacted)
    end

    it "is :offered after an offer" do
      OfficeOutreach.offer!(user: user, office: office)
      expect(OfficeOutreach.status_for(user)).to eq(:offered)
    end

    it "is :declined when the latest outreach is a decline" do
      OfficeOutreach.offer!(user: user, office: office)
      OfficeOutreach.decline!(user: user, office: office)
      expect(OfficeOutreach.status_for(user)).to eq(:declined)
    end

    it "reflects the most recent outreach when re-offered after a decline" do
      OfficeOutreach.decline!(user: user, office: office)
      OfficeOutreach.offer!(user: user, office: office)
      expect(OfficeOutreach.status_for(user)).to eq(:offered)
    end

    it "is :leased when the person holds an active office lease, regardless of outreach" do
      OfficeOutreach.offer!(user: user, office: office)
      create(:office_lease, organization: nil, user: user, operator: operator, location: location, office: office)
      expect(OfficeOutreach.status_for(user)).to eq(:leased)
    end

    it "honors a preloaded latest-outreach kind (no query)" do
      expect(OfficeOutreach.status_for(user, latest_outreach_kind: "office_offered")).to eq(:offered)
      expect(OfficeOutreach.status_for(user, latest_outreach_kind: nil)).to eq(:not_contacted)
    end
  end
end
