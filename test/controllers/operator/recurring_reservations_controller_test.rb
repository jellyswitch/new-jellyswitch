require "test_helper"

class Operator::RecurringReservationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    setup_initial_user_fixtures
    @room = rooms(:small_meeting_room)
    @params = {
      room_id: @room.id,
      recurrence_pattern: "weekly",
      duration_minutes: 60,
      time_of_day: "10:00",
      day_of_week: 2,
      start_date: Date.current.next_occurring(:tuesday).to_s,
      period_months: 1,
    }
  end

  # Regression: Pundit infers the policy query from the action name, so
  # `authorize :recurring_reservation` in #check_conflicts calls
  # RecurringReservationPolicy#check_conflicts? — which didn't exist, and
  # every conflict-preview request on the new-series form 500'd with
  # NoMethodError (Honeybadger fault 132566110, Choose Folsom).
  test "admin can preview conflicts for a new series" do
    log_in users(:cowork_tahoe_admin)

    post check_conflicts_recurring_reservations_path, params: @params, env: default_env

    assert_response :success
  end

  test "member is denied the conflict preview" do
    log_in users(:cowork_tahoe_member)

    post check_conflicts_recurring_reservations_path, params: @params, env: default_env

    assert_response :redirect
  end
end
