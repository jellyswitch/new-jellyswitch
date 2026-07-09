require "rails_helper"

RSpec.describe Notifiable::OfficeVacancy do
  let(:operator) { create(:operator) }
  let(:location) { create(:location, operator: operator) }
  let(:office)   { create(:office, operator: operator, location: location, name: "Pipkin Suite") }
  let!(:admin)   { create(:user, operator: operator, role: "admin", current_location: location, original_location: location) }

  subject { described_class.new(office) }

  def add_waiter
    u = create(:user, operator: operator, original_location: location)
    InterestTag.record(user: u, product: "office", source: "concierge")
    u
  end

  describe "the factory resolves it" do
    it "maps the OfficeVacancy type to this adapter" do
      expect(NotifiableFactory.for(office, "OfficeVacancy")).to be_a(described_class)
    end
  end

  describe "#message" do
    it "names the office and the number waiting" do
      add_waiter
      expect(subject.send(:message)).to eq("Pipkin Suite is available — 1 person waiting for an office. Notify them?")
    end
  end

  describe "#recipients" do
    it "targets the operator's admins for the location" do
      expect(subject.send(:recipients)).to include(admin)
    end
  end

  describe "#should_send_notification?" do
    it "is true only when someone is waiting" do
      expect(subject.send(:should_send_notification?)).to be false
      add_waiter
      expect(described_class.new(office).send(:should_send_notification?)).to be true
    end
  end

  describe "#deep_link_data" do
    it "deep-links to the office queue" do
      expect(subject.send(:deep_link_data)).to eq({ type: "office_waitlist", resource_id: office.id, path: "/people/waitlist" })
    end
  end

  describe "#create_feed_item" do
    it "creates no feed item (push only)" do
      expect { subject.send(:create_feed_item) }.not_to change(FeedItem, :count)
    end
  end
end
