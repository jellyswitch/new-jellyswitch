require "test_helper"

class Api::V1::DayPassesRescheduleTest < ActionDispatch::IntegrationTest
  setup do
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
    @member = users(:cowork_tahoe_member)
    @pass = day_passes(:cowork_tahoe_day_pass)
    @pass.update_columns(location_id: @location.id, day: 2.days.from_now.to_date)
    @tz = ActiveSupport::TimeZone[@location.time_zone]
  end

  def headers(user = @member)
    token = JWT.encode(
      { user_id: user.id, operator_id: @operator.id, exp: 30.days.from_now.to_i },
      Rails.application.secret_key_base,
      "HS256",
    )
    { "Authorization" => "Bearer #{token}", "X-Operator-Subdomain" => @operator.subdomain }
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

  test "move succeeds when the target day has capacity under the limit" do
    @pass.day_pass_type.update!(daily_limit: 2)
    target = 5.days.from_now.to_date

    patch "/api/v1/day_passes/#{@pass.id}/reschedule",
          params: { day: target.iso8601 }, headers: headers

    assert_response :success
    assert_equal target, @pass.reload.day
  end
end
