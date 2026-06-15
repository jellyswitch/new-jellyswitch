require "test_helper"

class Operator::RoomsControllerTest < ActionDispatch::IntegrationTest
  setup do
    setup_initial_user_fixtures
    @room = rooms(:small_meeting_room)
  end

  # Regression: Tahoe Longhouse lockout. A Pundit denial on room update must be
  # handled by the framework's clean user_not_authorized handler, not swallowed
  # by the controller's broad `rescue Exception` — which surfaced the raw
  # "not allowed to RoomPolicy#update? this Room" message to the end user.
  test "denied room update is handled cleanly without leaking the policy name" do
    log_in users(:cowork_tahoe_member)

    patch room_path(@room, params: { room: { name: "Hijacked" } }), env: default_env

    assert_no_match(/RoomPolicy/, flash.to_h.values.join(" "),
      "Pundit policy internals must not leak into a user-facing flash")
    assert_no_match(/An error occurred/, flash.to_h.values.join(" "))
    assert_equal "Meeting Room 3B", @room.reload.name
  end
end
