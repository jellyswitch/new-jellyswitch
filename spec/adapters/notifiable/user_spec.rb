require "rails_helper"

RSpec.describe Notifiable::User do
  let(:operator) { create(:operator) }
  let(:user) { create(:user, operator: operator) }

  subject { described_class.new(user) }

  describe "#create_feed_item" do
    it "creates a new-user FeedItem the first time" do
      expect {
        subject.send(:create_feed_item)
      }.to change { FeedItem.where(user_id: user.id).where("blob->>'type' = ?", "new-user").count }.from(0).to(1)
    end

    it "does not duplicate on a second call (e.g. admin approval after signup)" do
      subject.send(:create_feed_item)
      expect {
        subject.send(:create_feed_item)
      }.not_to change { FeedItem.where(user_id: user.id).where("blob->>'type' = ?", "new-user").count }
    end

    it "is scoped per (user, operator) so unrelated FeedItems do not block creation" do
      other_user = create(:user, operator: operator)
      FeedItem.create!(user_id: other_user.id, operator_id: operator.id, blob: { type: "new-user" })
      expect {
        subject.send(:create_feed_item)
      }.to change { FeedItem.where(user_id: user.id).where("blob->>'type' = ?", "new-user").count }.from(0).to(1)
    end
  end

  describe "#should_send_notification?" do
    it "respects operator.signup_notifications?" do
      operator.update!(signup_notifications: true)
      expect(subject.send(:should_send_notification?)).to be true
    end
  end
end
