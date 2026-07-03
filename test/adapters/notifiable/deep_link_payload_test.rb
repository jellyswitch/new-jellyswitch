require "test_helper"

# expo-notifications only exposes a remote push's data to the JS tap handler
# when it arrives under a "body" key — userInfo["body"] on iOS
# (EXNotificationSerializer), a JSON string at data["body"] on Android FCM
# (NotificationData#body). These tests lock in that nesting: flattening the
# payload back to top-level keys silently kills every notification deep link
# on real devices (local-notification tests won't catch it).
class NotifiableDeepLinkPayloadTest < ActiveSupport::TestCase
  DEEP_LINK = { type: "member_feedback", resource_id: 42, path: "/member_feedbacks/42" }.freeze

  class FakeNotifiable < Notifiable::Default
    def deep_link_data
      DEEP_LINK.dup
    end

    def message
      "New reply on member feedback"
    end
  end

  class NoLinkNotifiable < FakeNotifiable
    def deep_link_data
      {}
    end
  end

  setup do
    @user = users(:cowork_tahoe_admin)
    @user.android_token = "android-token-123"
  end

  test "android payload nests deep-link data as a JSON string under body" do
    payload = FakeNotifiable.new(Object.new).android_payload(@user)

    assert_equal ["body"], payload["data"].keys
    assert_kind_of String, payload["data"]["body"]
    parsed = JSON.parse(payload["data"]["body"])
    assert_equal "member_feedback", parsed["type"]
    assert_equal 42, parsed["resource_id"]
    assert_equal "/member_feedbacks/42", parsed["path"]
  end

  test "android payload omits data when there is no deep link" do
    payload = NoLinkNotifiable.new(Object.new).android_payload(@user)

    assert_nil payload["data"]
    assert_equal "android-token-123", payload[:token]
  end

  test "ios custom payload nests deep-link data under body" do
    notification = IosNotification.new(user: @user, message: "hi", data: DEEP_LINK.dup)

    assert_equal({ "body" => DEEP_LINK.dup }, notification.custom_payload)
  end

  test "ios custom payload is nil when there is no deep link" do
    notification = IosNotification.new(user: @user, message: "hi", data: {})

    assert_nil notification.custom_payload
  end
end
