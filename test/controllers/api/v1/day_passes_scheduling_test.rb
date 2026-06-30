require "test_helper"

class Api::V1::DayPassesSchedulingTest < ActionDispatch::IntegrationTest
  setup do
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
    @member = nil
    ActsAsTenant.with_tenant(@operator) do
      @member = create(:user, operator: @operator, original_location: @location, current_location: @location)
      dpt = DayPassType.create!(operator: @operator, location: @location, name: "5-Pack",
                                amount_in_cents: 20000, quantity: 5, available: true, visible: true)
      @bundle = DayPassBundle.create!(user: @member, operator: @operator, location: @location,
                                      day_pass_type: dpt, quantity_purchased: 5, passes_remaining: 5,
                                      purchased_at: Time.current)
    end
  end

  def headers(user)
    token = JWT.encode({ user_id: user.id, exp: 30.days.from_now.to_i }, Rails.application.secret_key_base, "HS256")
    { "Authorization" => "Bearer #{token}", "X-Operator-Subdomain" => @operator.subdomain, "Content-Type" => "application/json" }
  end

  test "POST schedule reserves the requested future days" do
    dates = [(Date.current + 1).iso8601, (Date.current + 3).iso8601]
    post "/api/v1/day_passes/schedule", params: { dates: dates }.to_json, headers: headers(@member)
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "scheduled", body["status"]
    assert_equal dates.sort, body["scheduled_days"].sort
    assert_equal 3, body["passes_remaining"]
  end

  test "GET scheduled_days lists only upcoming bundle days" do
    ActsAsTenant.with_tenant(@operator) do
      Billing::DayPassBundles::ScheduleDay.call(user: @member, location: @location, date: Date.current + 2, performed_by: @member)
    end
    get "/api/v1/day_passes/scheduled_days", headers: headers(@member)
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal 1, body.size
    assert_equal (Date.current + 2).iso8601, body.first["day"]
    assert body.first["id"].present?
  end

  test "POST cancel_scheduled restores the pass" do
    dp = nil
    ActsAsTenant.with_tenant(@operator) do
      dp = Billing::DayPassBundles::ScheduleDay.call(user: @member, location: @location, date: Date.current + 2, performed_by: @member).day_pass
    end
    post "/api/v1/day_passes/#{dp.id}/cancel_scheduled", headers: headers(@member)
    assert_response :success
    assert_equal "cancelled", JSON.parse(response.body)["status"]
    assert_equal 5, @bundle.reload.passes_remaining
  end

  test "a member cannot cancel another member's scheduled day" do
    other = nil
    ActsAsTenant.with_tenant(@operator) do
      other = create(:user, operator: @operator, original_location: @location, current_location: @location)
    end
    dp = nil
    ActsAsTenant.with_tenant(@operator) do
      dp = Billing::DayPassBundles::ScheduleDay.call(user: @member, location: @location, date: Date.current + 2, performed_by: @member).day_pass
    end
    post "/api/v1/day_passes/#{dp.id}/cancel_scheduled", headers: headers(other)
    assert_response :not_found
  end
end
