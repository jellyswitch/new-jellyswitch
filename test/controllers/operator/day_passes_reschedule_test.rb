require "test_helper"

class Operator::DayPassesRescheduleTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

  setup do
    setup_initial_user_fixtures
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
    @pass = day_passes(:cowork_tahoe_day_pass)
    @pass.update_columns(location_id: @location.id, day: 2.days.from_now.to_date)
    @tz = ActiveSupport::TimeZone[@location.time_zone]

    # Day Office pool (Task 9 / ADR 0026) — mirrors Api::V1::DayPassesRescheduleTest.
    @office_type = DayPassType.create!(name: "Day Office", operator: @operator, location: @location,
                                       kind: "day_office", amount_in_cents: 7500,
                                       included_meeting_room_minutes: 0, available: true, visible: true)
    @room_a = Room.create!(name: "A", operator: @operator, location: @location)
    @room_b = Room.create!(name: "B", operator: @operator, location: @location)
    @office_type.assign_office_rooms!({ @room_a.id => 1, @room_b.id => 2 })
  end

  # A purchased-and-allocated Day Office pass for the fixture member on `day`.
  def office_pass!(day)
    member = users(:cowork_tahoe_member)
    pass = DayPass.create!(user: member, billable: member, operator: @operator, location: @location,
                           day_pass_type: @office_type, day: day, imported: true)
    DayOffices::Allocator.allocate!(day_pass: pass)
    pass
  end

  test "admin moves a member's unused pass" do
    log_in users(:cowork_tahoe_admin)
    target = 7.days.from_now.to_date

    patch reschedule_day_pass_path(@pass), params: { day: target.iso8601 }, env: default_env

    assert_redirected_to user_admin_day_passes_path(@pass.user)
    assert_equal target, @pass.reload.day
  end

  test "a staff move emails the member a confirmation" do
    log_in users(:cowork_tahoe_admin)
    original = @pass.day
    target = 7.days.from_now.to_date

    assert_enqueued_email_with UserMailer, :day_pass_rescheduled, args: [@pass.id, original] do
      patch reschedule_day_pass_path(@pass), params: { day: target.iso8601 }, env: default_env
    end
    assert_equal target, @pass.reload.day
  end

  test "a rejected staff move sends no email" do
    log_in users(:cowork_tahoe_admin)

    assert_no_enqueued_emails do
      patch reschedule_day_pass_path(@pass), params: { day: 2.days.ago.to_date.iso8601 }, env: default_env
    end
  end

  test "member cannot use the staff reschedule endpoint" do
    log_in users(:cowork_tahoe_member)
    original = @pass.day

    patch reschedule_day_pass_path(@pass), params: { day: 7.days.from_now.to_date.iso8601 }, env: default_env

    assert_response :redirect
    assert_equal original, @pass.reload.day
  end

  test "a used pass is not moved" do
    log_in users(:cowork_tahoe_admin)
    d = @pass.day
    Checkin.create!(user: @pass.user, billable: @pass.user, location: @location,
                    datetime_in: @tz.local(d.year, d.month, d.day, 10, 0))

    patch reschedule_day_pass_path(@pass), params: { day: 9.days.from_now.to_date.iso8601 }, env: default_env

    assert_equal d, @pass.reload.day
    assert_match "already used", flash[:error]
  end

  test "a past date is rejected" do
    log_in users(:cowork_tahoe_admin)
    original = @pass.day

    patch reschedule_day_pass_path(@pass), params: { day: 2.days.ago.to_date.iso8601 }, env: default_env

    assert_equal original, @pass.reload.day
    assert_match "future date", flash[:error]
  end

  # --- Day Office: reschedule moves the hold (Task 9 / ADR 0026) -----------

  test "an office pass reschedule moves its hold to the new date" do
    log_in users(:cowork_tahoe_admin)
    pass = office_pass!(2.days.from_now.to_date)
    target = 7.days.from_now.to_date

    patch reschedule_day_pass_path(pass), params: { day: target.iso8601 }, env: default_env

    assert_redirected_to user_admin_day_passes_path(pass.user)
    assert_equal target, pass.reload.day
    hold = pass.reload_office_hold
    assert_equal target, hold.datetime_in.to_date
    assert_match "moved", flash[:success]
  end

  test "an office pass reschedule to a full target date flashes an error and changes nothing" do
    log_in users(:cowork_tahoe_admin)
    pass = office_pass!(2.days.from_now.to_date)
    original_day = pass.day
    original_hold_id = pass.office_hold.id
    target = 7.days.from_now.to_date
    span = @location.posted_hours_span(target)
    other = users(:cowork_tahoe_non_member)
    [@room_a, @room_b].each { |r| Reservation.create!(user: other, room: r, datetime_in: span.first, minutes: 600) }

    patch reschedule_day_pass_path(pass), params: { day: target.iso8601 }, env: default_env

    assert_redirected_to user_admin_day_passes_path(pass.user)
    assert_equal original_day, pass.reload.day
    assert_equal original_hold_id, pass.reload_office_hold&.id
    assert_match "fully booked", flash[:error]
  end
end
