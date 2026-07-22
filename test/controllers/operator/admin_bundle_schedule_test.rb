require "test_helper"

# Web parity with the mobile admin bundle scheduler: from a member's Day Passes
# admin page, staff can burn a bundle pass for TODAY (member at the front desk
# without the app), reserve a future day, and return a scheduled day to the
# pack. Same interactors as the mobile API; staff bypass the daily cap.
class Operator::AdminBundleScheduleTest < ActionDispatch::IntegrationTest
  setup do
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
    @admin    = users(:cowork_tahoe_admin)
    host! "#{@operator.subdomain}.example.com"
    ActsAsTenant.with_tenant(@operator) do
      @member = create(:user, operator: @operator, original_location: @location, current_location: @location)
      dpt = DayPassType.create!(operator: @operator, location: @location, name: "5-Pack",
                                amount_in_cents: 20000, quantity: 5, available: true, visible: true)
      @bundle = DayPassBundle.create!(user: @member, operator: @operator, location: @location,
                                      day_pass_type: dpt, quantity_purchased: 5, passes_remaining: 5,
                                      purchased_at: Time.current)
    end
  end

  # "Today" as the controller and interactor see it — the location's timezone,
  # not the test process's. Keeps the burn-today assertions stable at any hour.
  def location_today
    tz = ActiveSupport::TimeZone[@location.time_zone.presence || "UTC"]
    Time.current.in_time_zone(tz).to_date
  end

  test "admin burns a pass for today" do
    log_in @admin

    post user_day_pass_bundle_schedules_path(@member),
         params: { day: location_today.iso8601 }, env: default_env

    assert_redirected_to user_admin_day_passes_path(@member)
    assert_match "Burned a pass", flash[:notice]
    assert_equal 4, @bundle.reload.passes_remaining
    assert @member.day_passes.for_day(location_today).exists?
  end

  test "admin reserves a future day" do
    log_in @admin

    post user_day_pass_bundle_schedules_path(@member),
         params: { day: (location_today + 3).iso8601 }, env: default_env

    assert_redirected_to user_admin_day_passes_path(@member)
    assert_match "Reserved a pass", flash[:notice]
    assert_equal 4, @bundle.reload.passes_remaining
    assert @member.day_passes.for_day(location_today + 3).exists?
  end

  test "admin returns a scheduled day to the pack" do
    dp = nil
    ActsAsTenant.with_tenant(@operator) do
      dp = Billing::DayPassBundles::ScheduleDay.call(
        user: @member, location: @location, date: location_today + 2, performed_by: @admin).day_pass
    end
    assert_equal 4, @bundle.reload.passes_remaining
    log_in @admin

    delete user_day_pass_bundle_schedule_path(@member, dp), env: default_env

    assert_redirected_to user_admin_day_passes_path(@member)
    assert_match "Returned the pass", flash[:notice]
    assert_equal 5, @bundle.reload.passes_remaining
    assert_not DayPass.exists?(dp.id)
  end

  test "double-covering a day is refused and burns nothing" do
    log_in @admin
    post user_day_pass_bundle_schedules_path(@member),
         params: { day: (location_today + 1).iso8601 }, env: default_env
    assert_equal 4, @bundle.reload.passes_remaining

    post user_day_pass_bundle_schedules_path(@member),
         params: { day: (location_today + 1).iso8601 }, env: default_env

    assert_match "already has coverage", flash[:alert]
    assert_equal 4, @bundle.reload.passes_remaining
  end

  test "a non-admin member cannot use the endpoint" do
    log_in users(:cowork_tahoe_non_member)

    post user_day_pass_bundle_schedules_path(@member),
         params: { day: location_today.iso8601 }, env: default_env

    assert_match "Not authorized", flash[:alert]
    assert_equal 5, @bundle.reload.passes_remaining
  end

  # The Restore button posts to a slug URL (user.to_param = friendly_id slug);
  # plain users.find raised RecordNotFound, so the shipped button 404ed.
  test "restore-a-pass works via the slug URL" do
    ActsAsTenant.with_tenant(@operator) do
      Billing::DayPassBundles::ScheduleDay.call(
        user: @member, location: @location, date: location_today + 2, performed_by: @admin)
    end
    assert_equal 4, @bundle.reload.passes_remaining
    log_in @admin

    post user_day_pass_bundle_restores_path(@member),
         params: { day_pass_bundle_id: @bundle.id, reason: "admin restore" }, env: default_env

    assert_match "Restored a pass", flash[:notice]
    assert_equal 5, @bundle.reload.passes_remaining
  end

  test "the admin day passes page shows the use-a-pass control and return-to-pack" do
    ActsAsTenant.with_tenant(@operator) do
      Billing::DayPassBundles::ScheduleDay.call(
        user: @member, location: @location, date: location_today + 2, performed_by: @admin)
    end
    log_in @admin

    get user_admin_day_passes_path(@member), env: default_env

    assert_response :success
    assert_select "form[action=?]", user_day_pass_bundle_schedules_path(@member)
    assert_match "Return to pack", response.body
    assert_match "(from pack)", response.body
  end
end
