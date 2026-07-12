require "test_helper"

class Operator::DayPassesRescheduleTest < ActionDispatch::IntegrationTest
  setup do
    setup_initial_user_fixtures
    @location = locations(:cowork_tahoe_location)
    @pass = day_passes(:cowork_tahoe_day_pass)
    @pass.update_columns(location_id: @location.id, day: 2.days.from_now.to_date)
    @tz = ActiveSupport::TimeZone[@location.time_zone]
  end

  test "admin moves a member's unused pass" do
    log_in users(:cowork_tahoe_admin)
    target = 7.days.from_now.to_date

    patch reschedule_day_pass_path(@pass), params: { day: target.iso8601 }, env: default_env

    assert_redirected_to user_admin_day_passes_path(@pass.user)
    assert_equal target, @pass.reload.day
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
end
