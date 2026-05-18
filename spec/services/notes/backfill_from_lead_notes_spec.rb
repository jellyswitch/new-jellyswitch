require "rails_helper"

RSpec.describe Notes::BackfillFromLeadNotes do
  let(:operator) { create(:operator) }
  let(:location) { create(:location, operator: operator) }
  let(:author) { create(:user, operator: operator, current_location: location) }
  let(:noted_user) { create(:user, operator: operator, current_location: location) }
  let(:lead) { Lead.create!(user: noted_user, operator: operator) }

  it "copies each LeadNote into a Note with the right notable / author / operator / body" do
    ln = lead.lead_notes.create!(user: author, content: "Walked through the lounge")

    result = described_class.call
    expect(result[:created]).to eq(1)

    note = Note.where(notable: noted_user).last
    expect(note.author).to eq(author)
    expect(note.operator).to eq(operator)
    expect(note.body.to_plain_text).to include("Walked through the lounge")
    expect(note.created_at.to_i).to eq(ln.created_at.to_i)
  end

  it "is idempotent — running twice copies each LeadNote exactly once" do
    lead.lead_notes.create!(user: author, content: "First note")
    lead.lead_notes.create!(user: author, content: "Second note")

    first  = described_class.call
    second = described_class.call

    expect(first[:created]).to eq(2)
    expect(second[:created]).to eq(0)
    expect(second[:skipped]).to eq(2)
    expect(Note.where(notable: noted_user).count).to eq(2)
  end

  it "does NOT double-write Activity rows (the LeadNote.after_create callback already wrote them)" do
    lead.lead_notes.create!(user: author, content: "Original note")
    activity_count_before = Activity.where(user: noted_user, kind: "note").count

    described_class.call

    expect(Activity.where(user: noted_user, kind: "note").count).to eq(activity_count_before)
  end

  it "preserves rich-text formatting on backfill" do
    lead.lead_notes.create!(user: author, content: "<p>Has <strong>bold</strong> text</p>")
    described_class.call
    note = Note.where(notable: noted_user).last
    expect(note.body.to_s).to include("<strong>bold</strong>")
  end
end
