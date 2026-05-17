require "rails_helper"

RSpec.describe Note, type: :model do
  let(:operator) { create(:operator) }
  let(:location) { create(:location, operator: operator) }
  let(:author) { create(:user, operator: operator, current_location: location, role: "admin") }
  let(:noted_user) { create(:user, operator: operator, current_location: location) }
  let(:organization) { create(:organization, operator: operator) }

  it "requires a body" do
    note = Note.new(notable: noted_user, operator: operator, author: author)
    expect(note).not_to be_valid
    expect(note.errors[:body]).to include("can't be blank")
  end

  it "attaches polymorphically to a User" do
    note = Note.create!(notable: noted_user, operator: operator, author: author, body: "Talked at front desk")
    expect(noted_user.notes).to include(note)
    expect(note.notable).to eq(noted_user)
  end

  it "attaches polymorphically to an Organization" do
    note = Note.create!(notable: organization, operator: operator, author: author, body: "Renewal pending")
    expect(organization.notes).to include(note)
    expect(note.notable).to eq(organization)
  end

  describe ".recent" do
    it "orders newest first" do
      older = Note.create!(notable: noted_user, operator: operator, author: author, body: "older", created_at: 1.day.ago)
      newer = Note.create!(notable: noted_user, operator: operator, author: author, body: "newer")
      expect(noted_user.notes.recent.to_a).to eq([newer, older])
    end
  end
end
