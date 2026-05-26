# == Schema Information
#
# Table name: notes
#
#  id           :bigint(8)        not null, primary key
#  notable_type :string           not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  author_id    :bigint(8)        not null
#  notable_id   :bigint(8)        not null
#  operator_id  :bigint(8)        not null
#
# Indexes
#
#  index_notes_on_author_id                   (author_id)
#  index_notes_on_notable                     (notable_type,notable_id)
#  index_notes_on_operator_id                 (operator_id)
#  index_notes_on_operator_id_and_created_at  (operator_id,created_at)
#
# Foreign Keys
#
#  fk_rails_...  (author_id => users.id)
#  fk_rails_...  (operator_id => operators.id)
#
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

  describe "after_create :log_activity" do
    it "logs an Activity(kind: 'note') when notable is a User" do
      noted_user; author; operator # pre-evaluate lets so factory callbacks don't pollute the count
      expect {
        Note.create!(notable: noted_user, operator: operator, author: author, body: "Walked through the lounge")
      }.to change { Activity.where(user: noted_user, kind: "note").count }.by(1)

      activity = Activity.where(user: noted_user, kind: "note").last
      expect(activity.operator).to eq(operator)
      expect(activity.payload["author_user_id"]).to eq(author.id)
      expect(activity.payload["author_name"]).to eq(author.name)
      expect(activity.payload["content_preview"]).to include("Walked through the lounge")
    end

    it "does NOT log an Activity when notable is non-User (e.g. Organization)" do
      organization; author; operator # pre-evaluate lets
      expect {
        Note.create!(notable: organization, operator: operator, author: author, body: "Renewal pending")
      }.not_to change { Activity.count }
    end

    it "truncates content_preview to ~140 chars" do
      long_body = "x" * 500
      Note.create!(notable: noted_user, operator: operator, author: author, body: long_body)
      activity = Activity.where(user: noted_user, kind: "note").last
      expect(activity.payload["content_preview"].length).to be <= 145
    end
  end
end
