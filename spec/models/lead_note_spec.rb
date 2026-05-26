# == Schema Information
#
# Table name: lead_notes
#
#  id         :bigint(8)        not null, primary key
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  lead_id    :integer          not null
#  user_id    :integer          not null
#
require "rails_helper"

RSpec.describe LeadNote, type: :model do
  describe "activity logging" do
    let(:prospect) { create(:user) }
    let(:author) { create(:user, name: "Staff Sarah") }
    let(:operator) { create(:operator) }
    let(:lead) { create(:lead, user: prospect, operator: operator) }

    it "creates exactly one :note Activity on create" do
      lead   # force creation (lead factory creates prospect User, which logs a signup Activity)
      author # ditto for author User
      expect {
        create(:lead_note, lead: lead, user: author)
      }.to change(Activity.where(kind: "note"), :count).by(1)
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
