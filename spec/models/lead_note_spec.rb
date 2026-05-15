require "rails_helper"

RSpec.describe LeadNote, type: :model do
  describe "activity logging" do
    let(:prospect) { create(:user) }
    let(:author) { create(:user, name: "Staff Sarah") }
    let(:operator) { create(:operator) }
    let(:lead) { create(:lead, user: prospect, operator: operator) }

    it "creates exactly one Activity of kind 'note' on create" do
      expect {
        create(:lead_note, lead: lead, user: author)
      }.to change(Activity, :count).by(1)

      expect(Activity.last.kind).to eq("note")
    end

    it "puts the activity on the prospect's timeline, not the author's" do
      create(:lead_note, lead: lead, user: author)
      activity = Activity.last

      expect(activity.user).to eq(prospect)
      expect(activity.user).not_to eq(author)
    end

    it "associates with the lead's operator" do
      create(:lead_note, lead: lead, user: author)
      expect(Activity.last.operator).to eq(operator)
    end

    it "denormalizes author and a content preview into payload" do
      note = create(:lead_note, lead: lead, user: author, content: "Walked in on Tuesday morning and asked about pricing.")
      payload = Activity.last.payload

      expect(payload["author_user_id"]).to eq(author.id)
      expect(payload["author_name"]).to eq("Staff Sarah")
      expect(payload["content_preview"]).to eq("Walked in on Tuesday morning and asked about pricing.")
    end

    it "truncates long content previews to 140 chars" do
      long = "x" * 200
      create(:lead_note, lead: lead, user: author, content: long)
      expect(Activity.last.payload["content_preview"].length).to eq(140)
    end
  end
end
