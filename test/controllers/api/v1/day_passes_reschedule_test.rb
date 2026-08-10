require "test_helper"

class Api::V1::DayPassesRescheduleTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

  setup do
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
    @member = users(:cowork_tahoe_member)
    @pass = day_passes(:cowork_tahoe_day_pass)
    @pass.update_columns(location_id: @location.id, day: 2.days.from_now.to_date)
    @tz = ActiveSupport::TimeZone[@location.time_zone]

    # Day Office pool (Task 9 / ADR 0026) — mirrors Api::V1::DayPassesControllerTest.
    @office_type = DayPassType.create!(name: "Day Office", operator: @operator, location: @location,
                                       kind: "day_office", amount_in_cents: 7500,
                                       included_meeting_room_minutes: 0, available: true, visible: true)
    @room_a = Room.create!(name: "A", operator: @operator, location: @location)
    @room_b = Room.create!(name: "B", operator: @operator, location: @location)
    @office_type.assign_office_rooms!({ @room_a.id => 1, @room_b.id => 2 })
  end

  def headers(user = @member)
    token = JWT.encode(
      { user_id: user.id, operator_id: @operator.id, exp: 30.days.from_now.to_i },
      Rails.application.secret_key_base,
      "HS256",
    )
    { "Authorization" => "Bearer #{token}", "X-Operator-Subdomain" => @operator.subdomain }
  end

  # A purchased-and-allocated Day Office pass for @member on `day`.
  def office_pass!(day)
    pass = DayPass.create!(user: @member, billable: @member, operator: @operator, location: @location,
                           day_pass_type: @office_type, day: day, imported: true)
    DayOffices::Allocator.allocate!(day_pass: pass)
    pass
  end

  test "member moves an unused pass to a future date" do
    target = 5.days.from_now.to_date

    patch "/api/v1/day_passes/#{@pass.id}/reschedule", params: { day: target.iso8601 }, headers: headers

    assert_response :success
    assert_equal target, @pass.reload.day
    assert_equal "rescheduled", JSON.parse(response.body)["status"]
  end

  test "a missed (past) unused pass can still be moved forward" do
    @pass.update_columns(day: 3.days.ago.to_date)
    target = 1.day.from_now.to_date

    patch "/api/v1/day_passes/#{@pass.id}/reschedule", params: { day: target.iso8601 }, headers: headers

    assert_response :success
    assert_equal target, @pass.reload.day
  end

  test "cannot move a pass into the past" do
    original = @pass.day

    patch "/api/v1/day_passes/#{@pass.id}/reschedule",
          params: { day: 2.days.ago.to_date.iso8601 }, headers: headers

    assert_response :unprocessable_entity
    assert_equal original, @pass.reload.day
  end

  test "a used pass cannot be moved" do
    d = @pass.day
    Checkin.create!(user: @member, billable: @member, location: @location,
                    datetime_in: @tz.local(d.year, d.month, d.day, 10, 0))

    patch "/api/v1/day_passes/#{@pass.id}/reschedule",
          params: { day: 9.days.from_now.to_date.iso8601 }, headers: headers

    assert_response :unprocessable_entity
    assert_equal d, @pass.reload.day
  end

  test "cannot move another member's pass" do
    other = users(:cowork_tahoe_non_member)

    patch "/api/v1/day_passes/#{@pass.id}/reschedule",
          params: { day: 5.days.from_now.to_date.iso8601 }, headers: headers(other)

    assert_response :not_found
  end

  test "a garbage date is rejected" do
    patch "/api/v1/day_passes/#{@pass.id}/reschedule",
          params: { day: "not-a-date" }, headers: headers

    assert_response :unprocessable_entity
  end

  test "index exposes can_reschedule" do
    get "/api/v1/my_day_passes", headers: headers

    assert_response :success
    row = JSON.parse(response.body).find { |p| p["id"] == @pass.id }
    assert_equal true, row["can_reschedule"]
  end

  test "cannot move a pass to a day at the type's daily limit" do
    @pass.day_pass_type.update!(daily_limit: 1)
    target = 5.days.from_now.to_date
    other = users(:cowork_tahoe_non_member)
    ActsAsTenant.with_tenant(@operator) do
      DayPass.create!(user: other, billable: other, operator: @operator, location: @location,
                      day_pass_type: @pass.day_pass_type, day: target, imported: true)
    end
    original = @pass.day

    patch "/api/v1/day_passes/#{@pass.id}/reschedule",
          params: { day: target.iso8601 }, headers: headers

    assert_response :unprocessable_entity
    assert_includes JSON.parse(response.body)["error"], "fully booked"
    assert_equal original, @pass.reload.day
  end

  test "a same-day 'move' is allowed even when the day is at the limit" do
    # The pass's own row fills the day — moving it onto its own day must not
    # count the pass against itself.
    @pass.day_pass_type.update!(daily_limit: 1)

    patch "/api/v1/day_passes/#{@pass.id}/reschedule",
          params: { day: @pass.day.iso8601 }, headers: headers

    assert_response :success
  end

  test "a successful move emails the member a confirmation" do
    original = @pass.day
    target = 5.days.from_now.to_date

    assert_enqueued_email_with UserMailer, :day_pass_rescheduled, args: [@pass.id, original] do
      patch "/api/v1/day_passes/#{@pass.id}/reschedule", params: { day: target.iso8601 }, headers: headers
    end
    assert_response :success
  end

  test "a same-day 'move' sends no email" do
    assert_no_enqueued_emails do
      patch "/api/v1/day_passes/#{@pass.id}/reschedule",
            params: { day: @pass.day.iso8601 }, headers: headers
    end
    assert_response :success
  end

  test "a rejected move sends no email" do
    assert_no_enqueued_emails do
      patch "/api/v1/day_passes/#{@pass.id}/reschedule",
            params: { day: 2.days.ago.to_date.iso8601 }, headers: headers
    end
    assert_response :unprocessable_entity
  end

  test "move succeeds when the target day has capacity under the limit" do
    @pass.day_pass_type.update!(daily_limit: 2)
    target = 5.days.from_now.to_date

    patch "/api/v1/day_passes/#{@pass.id}/reschedule",
          params: { day: target.iso8601 }, headers: headers

    assert_response :success
    assert_equal target, @pass.reload.day
  end

  # --- Day Office: reschedule moves the hold (Task 9 / ADR 0026) -----------

  test "an office pass reschedule moves its hold to the new date" do
    pass = office_pass!(2.days.from_now.to_date)
    original = pass.day
    target = 5.days.from_now.to_date

    assert_enqueued_email_with UserMailer, :day_pass_rescheduled, args: [pass.id, original] do
      patch "/api/v1/day_passes/#{pass.id}/reschedule", params: { day: target.iso8601 }, headers: headers
    end

    assert_response :success
    assert_equal target, pass.reload.day
    hold = pass.reload_office_hold
    assert_equal target, hold.datetime_in.to_date
    assert_equal 1, Reservation.unscoped.where(day_office_pass_id: pass.id, cancelled: true).count
    body = JSON.parse(response.body)
    assert_equal "#{hold.room.name} is yours #{hold.window_label}.", body["confirmation_note"]
  end

  test "an office pass reschedule is refused when the move is lost to a race" do
    pass = office_pass!(2.days.from_now.to_date)
    original_day = pass.day
    original_hold_id = pass.office_hold.id
    target = 5.days.from_now.to_date

    # The pool genuinely has room on `target` (the pre-check gate passes);
    # the allocator itself is stubbed to lose the race, the same shape a
    # real concurrent move produces between the pre-check and MoveHold's own
    # attempt. A literally-full target is instead caught earlier by the
    # daily_limit_reached? pre-check — both paths now render the identical
    # plain refusal (reschedule never offers the #create purchase-fallback
    # payload; see #reschedule). Mirrors Api::V1::DayPassesControllerTest's
    # #create race-backstop test.
    assert_no_enqueued_emails do
      DayOffices::Allocator.stub :allocate!, nil do
        patch "/api/v1/day_passes/#{pass.id}/reschedule", params: { day: target.iso8601 }, headers: headers
      end
    end

    assert_response :unprocessable_entity
    body = JSON.parse(response.body)
    assert_includes body["error"], "fully booked"
    assert_not body.key?("code")
    assert_equal original_day, pass.reload.day
    assert_equal original_hold_id, pass.reload_office_hold&.id
  end

  test "a same-day reschedule of an office pass keeps the same hold (no churn)" do
    pass = office_pass!(2.days.from_now.to_date)
    hold_id = pass.office_hold.id

    assert_no_enqueued_emails do
      patch "/api/v1/day_passes/#{pass.id}/reschedule", params: { day: pass.day.iso8601 }, headers: headers
    end

    assert_response :success
    assert_equal hold_id, pass.reload_office_hold.id
  end
end
