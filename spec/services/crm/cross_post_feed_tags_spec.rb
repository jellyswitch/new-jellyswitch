require "rails_helper"

RSpec.describe Crm::CrossPostFeedTags do
  let(:operator) { create(:operator) }
  let(:author)   { create(:user, operator: operator, role: "admin", name: "Adam Admin") }
  let(:member)   { create(:user, operator: operator, role: "unassigned", approved: true, name: "Jane Member") }
  let(:teammate) { create(:user, operator: operator, role: "general-manager", name: "Greg GM") }
  let(:source)   { create(:feed_item, operator: operator, user: author) }

  it "cross-posts a Note onto a tagged member — full text, author, and source" do
    member; teammate
    text = "Great chat with @Jane Member today, considering an upgrade."

    expect {
      described_class.call(text: text, source: source, author: author)
    }.to change { Note.where(notable: member).count }.by(1)

    note = Note.where(notable: member).last
    expect(note.author).to eq(author)
    expect(note.source).to eq(source)
    expect(note.body.to_plain_text).to include("considering an upgrade")
  end

  it "does NOT cross-post when only a staff teammate is tagged" do
    teammate
    text = "Heads up @Greg GM, please follow up."
    expect {
      described_class.call(text: text, source: source, author: author)
    }.not_to change(Note, :count)
  end

  it "does not cross-post the author tagging themselves" do
    text = "Note to self @Adam Admin follow up later"
    expect {
      described_class.call(text: text, source: source, author: author)
    }.not_to change(Note, :count)
  end

  it "matches whole names only — '@Jane Member' does not tag 'Jan'" do
    jan = create(:user, operator: operator, role: "unassigned", approved: true, name: "Jan")
    member
    described_class.call(text: "Spoke with @Jane Member", source: source, author: author)

    expect(Note.where(notable: member).count).to eq(1)
    expect(Note.where(notable: jan).count).to eq(0)
  end
end
