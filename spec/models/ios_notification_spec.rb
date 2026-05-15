require "rails_helper"

RSpec.describe IosNotification do
  let(:operator) { create(:operator, bundle_id: "com.test.app") }
  let(:user) { create(:user, operator: operator, ios_token: "test_token_123") }

  before do
    ENV["APNS_KEY_FILE"] = "-----BEGIN PRIVATE KEY-----\nfake_key_data\n-----END PRIVATE KEY-----"
    ENV["APNS_KEY_ID"] = "TESTKEY123"
    ENV["APNS_TEAM_ID"] = "TESTTEAM99"
  end

  after do
    ENV.delete("APNS_KEY_FILE")
    ENV.delete("APNS_KEY_ID")
    ENV.delete("APNS_TEAM_ID")
  end

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
    let(:connection) { instance_double(Apnotic::Connection, push: double(ok?: true, status: 200), close: nil) }

    before do
      allow(Apnotic::Connection).to receive(:new).and_return(connection)
    end

    it "creates connection with token-based auth" do
      described_class.new(user: user, message: "Test").send!

      expect(Apnotic::Connection).to have_received(:new).with(
        auth_method: :token,
        cert_path: an_instance_of(StringIO),
        key_id: "TESTKEY123",
        team_id: "TESTTEAM99"
      )
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

  describe "#validate!" do
    it "raises error when APNS_KEY_FILE is missing" do
      ENV.delete("APNS_KEY_FILE")
      expect { described_class.new(user: user, message: "Test").send! }.to raise_error("APNs key not configured")
    end

    it "raises error when bundle_id is missing" do
      operator.update(bundle_id: nil)
      expect { described_class.new(user: user, message: "Test").send! }.to raise_error("No Bundle ID")
    end

    it "raises error when ios_token is missing" do
      user.update(ios_token: nil)
      expect { described_class.new(user: user, message: "Test").send! }.to raise_error("No iOS token")
    end
  end
end
