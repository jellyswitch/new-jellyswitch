require "rails_helper"

RSpec.describe IosNotification do
  let(:operator) { create(:operator, bundle_id: "com.test.app") }
  let(:user) { create(:user, operator: operator, ios_token: "test_token_123") }

  describe "#initialize" do
    it "accepts data parameter" do
      notification = described_class.new(user: user, message: "Test", data: { type: "reservation", resource_id: 1 })
      expect(notification.data).to eq({ type: "reservation", resource_id: 1 })
    end

    it "defaults data to empty hash" do
      notification = described_class.new(user: user, message: "Test")
      expect(notification.data).to eq({})
    end
  end

  describe "#send!" do
    let(:data) { { type: "reservation", resource_id: 42, path: "/reservations/42" } }
    let(:connection) { instance_double(Apnotic::Connection, push: double(ok?: true), close: nil) }

    before do
      certificate = double(download: "fake_cert_data")
      allow(user.operator).to receive(:push_notification_certificate).and_return(certificate)
      allow(Apnotic::Connection).to receive(:new).and_return(connection)
    end

    it "sets custom_payload when data is present" do
      apns_notification = nil
      allow(Apnotic::Notification).to receive(:new).and_wrap_original do |method, *args|
        apns_notification = method.call(*args)
        apns_notification
      end

      described_class.new(user: user, message: "Test", data: data).send!

      expect(apns_notification.custom_payload).to eq(data)
    end

    it "does not set custom_payload when data is empty" do
      apns_notification = nil
      allow(Apnotic::Notification).to receive(:new).and_wrap_original do |method, *args|
        apns_notification = method.call(*args)
        apns_notification
      end

      described_class.new(user: user, message: "Test").send!

      expect(apns_notification.custom_payload).to be_nil
    end
  end
end
