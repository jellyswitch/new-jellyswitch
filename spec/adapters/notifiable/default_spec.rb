require "rails_helper"

RSpec.describe Notifiable::Default do
  # Minimal concrete subclass: the skip branches only need `operator` (via the
  # wrapped record) and `message`; `recipients` matters only when configured.
  let(:adapter_class) do
    Class.new(described_class) do
      def message
        "Test push"
      end

      def recipients
        []
      end
    end
  end

  let(:operator) { create(:operator) }
  let(:record) { Struct.new(:operator).new(operator) }

  subject(:adapter) { adapter_class.new(record) }

  before { Rails.cache.clear }

  describe "missing push config alerting" do
    context "iOS: bundle_id/APNs missing but users have registered ios tokens" do
      before { create(:user, operator: operator, ios_token: "ios-device-token") }

      it "notifies Honeybadger and still skips the send" do
        expect(Honeybadger).to receive(:notify).with(
          a_string_including("registered ios push tokens"),
          hash_including(
            error_class: "Notifiable::MissingPushConfig",
            fingerprint: "missing_push_config/#{operator.id}/ios",
            context: hash_including(operator_id: operator.id, platform: :ios, registered_token_count: 1)
          )
        )
        expect { adapter.ios }.not_to raise_error
      end

      it "alerts at most once per operator/platform per day" do
        expect(Honeybadger).to receive(:notify).once
        adapter.ios
        adapter.ios
      end

      it "does not consume the android gate" do
        create(:user, operator: operator, android_token: "android-device-token")
        expect(Honeybadger).to receive(:notify).twice
        adapter.ios
        adapter.android
      end
    end

    context "Android: firebase config missing but users have registered android tokens" do
      before { create(:user, operator: operator, android_token: "android-device-token") }

      it "notifies Honeybadger" do
        expect(Honeybadger).to receive(:notify).with(
          a_string_including("registered android push tokens"),
          hash_including(
            error_class: "Notifiable::MissingPushConfig",
            fingerprint: "missing_push_config/#{operator.id}/android",
            context: hash_including(operator_id: operator.id, platform: :android, registered_token_count: 1)
          )
        )
        adapter.android
      end
    end

    context "operator with no registered tokens (web-only)" do
      before { create(:user, operator: operator, ios_token: nil, android_token: "") }

      it "skips quietly without alerting" do
        expect(Honeybadger).not_to receive(:notify)
        adapter.ios
        adapter.android
      end
    end

    context "when push is fully configured" do
      before do
        operator.update!(bundle_id: "com.example.app")
        allow(adapter).to receive(:apns_configured?).and_return(true)
        create(:user, operator: operator, ios_token: "ios-device-token")
      end

      it "does not alert" do
        expect(Honeybadger).not_to receive(:notify)
        adapter.ios
      end
    end
  end
end
