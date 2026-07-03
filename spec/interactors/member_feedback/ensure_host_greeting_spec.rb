require "rails_helper"

RSpec.describe MemberFeedback::EnsureHostGreeting do
  let(:operator) { create(:operator) }
  let(:location) { create(:location, operator: operator, name: "Cowork Tahoe") }
  let(:host) { create(:user, operator: operator, role: User::ADMIN, name: "David Orr", original_location: location) }
  let(:visitor) { create(:user, operator: operator, original_location: location, name: "Alex Pine") }

  describe ".call" do
    it "creates a thread + greeting reply when none exists for the visitor" do
      expect {
        described_class.call(user: visitor, location: location, operator: operator, host: host)
      }.to change { visitor.member_feedbacks.where(location: location).count }.by(1)

      thread = visitor.member_feedbacks.where(location: location).first
      expect(thread.comment).to be_blank
      expect(thread.feedback_replies.count).to eq(1)

      greeting = thread.feedback_replies.first
      expect(greeting.user_id).to eq(host.id)
      expect(greeting.body).to include("Alex")
      expect(greeting.body).to include("Cowork Tahoe")
    end

    it "does NOT greet an established member (the greeting is a signup welcome)" do
      # A member re-logging in after an app update should not get a
      # "Welcome!" message years into their membership.
      visitor.update!(created_at: 2.years.ago)

      expect {
        described_class.call(user: visitor, location: location, operator: operator, host: host)
      }.not_to change { MemberFeedback.count }
    end

    it "still greets an account created within the new-member window" do
      visitor.update!(created_at: 6.days.ago)

      expect {
        described_class.call(user: visitor, location: location, operator: operator, host: host)
      }.to change { visitor.member_feedbacks.where(location: location).count }.by(1)
    end

    it "does not greet an account just past the new-member window" do
      visitor.update!(created_at: 8.days.ago)

      expect {
        described_class.call(user: visitor, location: location, operator: operator, host: host)
      }.not_to change { MemberFeedback.count }
    end

    it "is idempotent — no new thread when the visitor already has one" do
      create(:member_feedback, user: visitor, location: location, operator: operator)

      expect {
        described_class.call(user: visitor, location: location, operator: operator, host: host)
      }.not_to change { MemberFeedback.count }
    end

    it "is a no-op when there's no host to send from" do
      expect {
        described_class.call(user: visitor, location: location, operator: operator, host: nil)
      }.not_to change { MemberFeedback.count }
    end

    it "is a no-op when user, location, or operator are missing" do
      expect {
        described_class.call(user: nil, location: location, operator: operator, host: host)
      }.not_to change { MemberFeedback.count }
    end

    it "accepts a custom greeting override" do
      described_class.call(
        user: visitor, location: location, operator: operator, host: host,
        greeting: "Custom welcome!",
      )

      thread = visitor.member_feedbacks.where(location: location).first
      expect(thread.feedback_replies.first.body).to eq("Custom welcome!")
    end
  end
end
