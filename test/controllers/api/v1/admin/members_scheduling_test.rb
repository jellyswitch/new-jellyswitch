require "test_helper"

class Api::V1::Admin::MembersSchedulingTest < ActionDispatch::IntegrationTest
  setup do
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
    @admin    = users(:cowork_tahoe_admin)
    ActsAsTenant.with_tenant(@operator) do
      @member = create(:user, operator: @operator, original_location: @location, current_location: @location)
      dpt = DayPassType.create!(operator: @operator, location: @location, name: "5-Pack",
                                amount_in_cents: 20000, quantity: 5, available: true, visible: true)
      @bundle = DayPassBundle.create!(user: @member, operator: @operator, location: @location,
                                      day_pass_type: dpt, quantity_purchased: 5, passes_remaining: 5,
                                      purchased_at: Time.current)
    end
  end

  def headers
    token = JWT.encode({ user_id: @admin.id, exp: 30.days.from_now.to_i }, Rails.application.secret_key_base, "HS256")
    { "Authorization" => "Bearer #{token}", "X-Operator-Subdomain" => @operator.subdomain, "Content-Type" => "application/json" }
  end

  test "admin schedules days for a member" do
    post "/api/v1/admin/members/#{@member.id}/schedule_bundle_days",
         params: { dates: [(Date.current + 1).iso8601] }.to_json, headers: headers
    assert_response :success
    assert_equal "scheduled", JSON.parse(response.body)["status"]
    assert_equal 4, @bundle.reload.passes_remaining
  end

  test "admin lists then cancels a member's scheduled day" do
    dp = nil
    ActsAsTenant.with_tenant(@operator) do
      dp = Billing::DayPassBundles::ScheduleDay.call(user: @member, location: @location, date: Date.current + 2, performed_by: @member).day_pass
    end

    get "/api/v1/admin/members/#{@member.id}/scheduled_bundle_days", headers: headers
    assert_response :success
    assert_equal dp.id, JSON.parse(response.body).first["id"]

    post "/api/v1/admin/members/#{@member.id}/scheduled_bundle_days/#{dp.id}/cancel", headers: headers
    assert_response :success
    cancel_body = JSON.parse(response.body)
    assert_equal 5, @bundle.reload.passes_remaining
    assert_equal 5, cancel_body["passes_remaining"], "cancel response should include passes_remaining"
  end

  test "admin schedules a member onto a day at the limit (staff bypass)" do
    ActsAsTenant.with_tenant(@operator) do
      @bundle.day_pass_type.update!(daily_limit: 1)
      other = create(:user, operator: @operator, original_location: @location, current_location: @location)
      DayPass.create!(user: other, billable: other, operator: @operator, location: @location,
                      day_pass_type: @bundle.day_pass_type, day: Date.current + 1, imported: true)
    end

    post "/api/v1/admin/members/#{@member.id}/schedule_bundle_days",
         params: { dates: [(Date.current + 1).iso8601] }.to_json, headers: headers

    assert_response :success
    assert_equal 4, @bundle.reload.passes_remaining
  end
end
