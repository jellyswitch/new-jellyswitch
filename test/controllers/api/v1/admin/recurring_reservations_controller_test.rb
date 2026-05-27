require "test_helper"

# Coverage for /api/v1/admin/recurring_reservations#create — the endpoint
# the mobile admin's "Create Recurring Reservation" form hits.
#
# Two regressions the form had been silently sitting on top of:
#  1. The mobile only ever sent `day_of_week`/`time`/`duration`, missing
#     the model's required title / recurrence_pattern / time_of_day /
#     duration_minutes / start_date / end_date. The row never persisted;
#     admins thought "Created" but the list stayed empty.
#  2. The model only supported daily_weekdays / weekly / biweekly /
#     monthly. Admins asking for "daily" (incl. weekends) or "bimonthly"
#     (every 2 months) had no path.
#
# This test asserts the create endpoint accepts the full payload the new
# mobile form sends and persists the row, including for the two newly
# added patterns.
class Api::V1::Admin::RecurringReservationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin    = users(:cowork_tahoe_admin)
    @operator = operators(:cowork_tahoe)
    @member   = users(:cowork_tahoe_member)
    @room     = rooms(:small_meeting_room)

    @token = JWT.encode(
      { user_id: @admin.id, operator_id: @operator.id, exp: 30.days.from_now.to_i },
      Rails.application.secret_key_base,
      "HS256",
    )
  end

  def headers
    {
      "Authorization"        => "Bearer #{@token}",
      "X-Operator-Subdomain" => @operator.subdomain,
      "Content-Type"         => "application/json",
    }
  end

  def base_payload
    {
      user_id:           @member.id,
      room_id:           @room.id,
      title:             "Standing demo",
      recurrence_pattern: "weekly",
      duration_minutes:  60,
      time_of_day:       "10:00",
      start_date:        "2026-06-01",  # Monday
      end_date:          "2026-06-30",
      day_of_week:       1,             # Monday
    }
  end

  test "create persists a weekly series with the full mobile payload" do
    assert_difference -> { RecurringReservation.count }, +1 do
      post "/api/v1/admin/recurring_reservations",
           params:  base_payload.to_json,
           headers: headers
    end

    assert_response :created
    row = RecurringReservation.order(:id).last
    assert_equal "Standing demo", row.title
    assert_equal "weekly",        row.recurrence_pattern
    assert_equal 60,              row.duration_minutes
    assert_equal 1,               row.day_of_week
  end

  test "create accepts the newly added daily pattern (incl. weekends)" do
    payload = base_payload.merge(recurrence_pattern: "daily", day_of_week: nil)

    assert_difference -> { RecurringReservation.count }, +1 do
      post "/api/v1/admin/recurring_reservations",
           params: payload.to_json, headers: headers
    end
    assert_response :created

    row = RecurringReservation.order(:id).last
    assert_equal "daily", row.recurrence_pattern
    # Spans 2026-06-01..06-30 inclusive — daily must include weekends,
    # i.e. 30 occurrences. (daily_weekdays would have produced 22.)
    assert_equal 30, row.reservations.count
  end

  test "create accepts the newly added bimonthly pattern" do
    payload = base_payload.merge(
      recurrence_pattern: "bimonthly",
      day_of_week:        nil,
      day_of_month:       1,
      start_date:         "2026-01-01",
      end_date:           "2026-06-30",
    )

    assert_difference -> { RecurringReservation.count }, +1 do
      post "/api/v1/admin/recurring_reservations",
           params: payload.to_json, headers: headers
    end
    assert_response :created

    row = RecurringReservation.order(:id).last
    assert_equal "bimonthly", row.recurrence_pattern
    # Jan / Mar / May = 3 occurrences (Feb / Apr / Jun skipped).
    assert_equal 3, row.reservations.count
  end

  test "index payload exposes pattern_description so the list can render it" do
    RecurringReservation.create!(
      title:              "Monday demo",
      user:               @member,
      room:               @room,
      operator:           @operator,
      location:           locations(:cowork_tahoe_location),
      recurrence_pattern: "weekly",
      duration_minutes:   60,
      time_of_day:        Time.zone.parse("10:00"),
      start_date:         Date.new(2026, 6, 1),
      end_date:           Date.new(2026, 6, 30),
      day_of_week:        1,
    )

    get "/api/v1/admin/recurring_reservations", headers: headers
    assert_response :success

    row = JSON.parse(response.body).find { |r| r["recurrence_pattern"] == "weekly" }
    refute_nil row
    assert_equal "Every Monday", row["pattern_description"]
  end
end
