require 'rails_helper'

RSpec.describe Notifiable::Approval do
  let(:operator) { create(:operator) }
  let(:user) { create(:user, operator: operator) }

  subject { described_class.new(user) }

  describe "#message" do
    it "includes the operator name" do
      expect(subject.send(:message)).to eq("You've been approved! Welcome to #{operator.name}.")
    end
  end

  describe "#recipients" do
    it "returns the approved user" do
      expect(subject.send(:recipients)).to eq([user])
    end
  end

  describe "#deep_link_data" do
    it "returns approval deep link to /home" do
      expect(subject.send(:deep_link_data)).to eq({
        type: "approval",
        resource_id: user.id,
        path: "/home"
      })
    end
  end

  describe "#should_send_notification?" do
    it "returns true" do
      expect(subject.send(:should_send_notification?)).to be true
    end
  end

  describe "#create_feed_item" do
    it "does not create a feed item" do
      expect { subject.send(:create_feed_item) }.not_to change(FeedItem, :count)
    end
  end
end
