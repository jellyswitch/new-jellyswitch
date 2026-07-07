require "test_helper"

# Coverage for the mobile admin notification-settings endpoint
# (GET/PATCH /api/v1/admin/notifications_config).
#
# The endpoint originally exposed four toggle keys — new_member_notification,
# new_booking_notification, new_feedback_notification, daily_digest — that were
# NEVER columns on operators. The GET action hid this with operator.try(...)
# (always false), but PATCH called operator.update(...) with the fictional keys
# and raised ActiveModel::UnknownAttributeError, so a TLH admin toggling any
# notification and saving got a 500 and the preference could never persist.
#
# The keys now map to the real *_notifications boolean columns, and unknown
# keys are ignored so a stale client can never 500.
class Api::V1::Admin::SettingsNotificationsTest < ActionDispatch::IntegrationTest
  setup do
    @operator = operators(:cowork_tahoe)
    @admin    = users(:cowork_tahoe_admin)
    # Deterministic starting state, independent of fixture defaults.
    @operator.update!(
      signup_notifications: true,
      reservation_notifications: false,
      paid_room_reservation_notifications: true,
      member_feedback_notifications: false,
    )
  end

  def headers
    token = JWT.encode(
      { user_id: @admin.id, exp: 30.days.from_now.to_i },
      Rails.application.secret_key_base,
      "HS256",
    )
    {
      "Authorization"        => "Bearer #{token}",
      "X-Operator-Subdomain" => @operator.subdomain,
      "Content-Type"         => "application/json",
    }
  end

  test "GET returns the four mapped toggles reflecting the real operator columns" do
    get "/api/v1/admin/notifications_config", headers: headers
    assert_response :success

    body = JSON.parse(response.body)
    assert_equal(
      %w[new_member_notification free_room_booking_notification paid_room_booking_notification new_feedback_notification].sort,
      body.keys.sort,
    )
    assert_equal true,  body["new_member_notification"]        # signup_notifications
    assert_equal false, body["free_room_booking_notification"] # reservation_notifications
    assert_equal true,  body["paid_room_booking_notification"] # paid_room_reservation_notifications
    assert_equal false, body["new_feedback_notification"]      # member_feedback_notifications
  end

  test "GET no longer exposes the phantom daily_digest toggle" do
    get "/api/v1/admin/notifications_config", headers: headers
    assert_response :success
    assert_not_includes JSON.parse(response.body).keys, "daily_digest"
  end

  test "PATCH persists each toggle to its real operator column (no 500)" do
    patch "/api/v1/admin/notifications_config",
      params: {
        new_member_notification: false,
        free_room_booking_notification: true,
        paid_room_booking_notification: false,
        new_feedback_notification: true,
      }.to_json,
      headers: headers

    assert_response :success

    @operator.reload
    assert_equal false, @operator.signup_notifications
    assert_equal true,  @operator.reservation_notifications
    assert_equal false, @operator.paid_room_reservation_notifications
    assert_equal true,  @operator.member_feedback_notifications

    # Response echoes the freshly-persisted state so the client can reconcile.
    body = JSON.parse(response.body)
    assert_equal false, body["new_member_notification"]
    assert_equal true,  body["free_room_booking_notification"]
    assert_equal false, body["paid_room_booking_notification"]
    assert_equal true,  body["new_feedback_notification"]
  end

  test "PATCH free and paid room bookings are independently controllable" do
    patch "/api/v1/admin/notifications_config",
      params: { free_room_booking_notification: false, paid_room_booking_notification: true }.to_json,
      headers: headers
    assert_response :success

    @operator.reload
    assert_equal false, @operator.reservation_notifications
    assert_equal true,  @operator.paid_room_reservation_notifications
  end

  test "PATCH ignores unknown keys (incl. a stale client's daily_digest) without raising" do
    patch "/api/v1/admin/notifications_config",
      params: { daily_digest: true, some_bogus_key: true, new_member_notification: true }.to_json,
      headers: headers

    assert_response :success
    @operator.reload
    assert_equal true, @operator.signup_notifications
    # Nothing exploded and no phantom attribute was assigned.
    assert_not_includes JSON.parse(response.body).keys, "daily_digest"
  end
end
