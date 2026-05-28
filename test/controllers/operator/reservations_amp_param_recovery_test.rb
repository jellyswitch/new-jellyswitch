require "test_helper"

# Regression for Coleen's recurring Choose Folsom 404 (captured via the
# #431 telemetry on 2026-05-28):
#
#   GET /reservations/confirm?day=...&amp;duration=120&amp;room_id=5927&amp;...
#   → ActiveRecord::RecordNotFound (Couldn't find Room without an ID) → 404
#
# Root cause: the duration-slider builds the confirm link's href, Turbo's
# snapshot cache serializes the JS-set href via outerHTML (which re-escapes
# & → &amp;), and on a WebView cache-restore + navigation the literal "amp;"
# survives into the query string. Rails then parses the params as
# `amp;room_id` etc., leaving `params[:room_id]` nil.
#
# This test exercises the controller-side safety net: a before_action that
# re-maps any `amp;`-prefixed param key back to its intended name, so the
# reservation flow doesn't 404 even if a mangled URL slips through. (The
# primary fix is in the slider component — this is defense-in-depth for the
# whole flow.)
class Operator::ReservationsAmpParamRecoveryTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:cowork_tahoe_admin)
    @room  = rooms(:small_meeting_room)
  end

  test "choose_time recovers room_id from an amp;-prefixed key" do
    log_in @admin

    # Simulates the post-misparse param shape: only `day` keeps its real
    # key; everything after the first &amp; is prefixed with "amp;".
    get "/reservations/choose_time", params: {
      "day"          => "2026-12-15",
      "amp;room_id"  => @room.id,
      "amp;user_id"  => @admin.id,
    }, env: default_env

    assert_response :success,
      "choose_time should recover room_id from amp;room_id instead of 404ing"
  end

  test "choose_time still works with normal (un-mangled) params" do
    log_in @admin

    get "/reservations/choose_time", params: {
      "day"     => "2026-12-15",
      "room_id" => @room.id,
      "user_id" => @admin.id,
    }, env: default_env

    assert_response :success
  end
end
