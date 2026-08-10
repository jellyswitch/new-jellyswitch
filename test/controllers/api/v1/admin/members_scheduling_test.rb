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

  # --- Unscheduled +/- (admin_burn / admin_restore, no date attached) -------

  test "admin burns an unscheduled pass — admin_burn ledger row, no DayPass" do
    assert_no_difference -> { DayPass.count } do
      post "/api/v1/admin/members/#{@member.id}/burn_bundle_pass",
           params: { reason: "walked in on the old system" }.to_json, headers: headers
    end

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "burned", body["status"]
    assert_equal 4, body["passes_remaining"]
    assert_equal 4, @bundle.reload.passes_remaining

    redemption = @bundle.redemptions.order(:id).last
    assert_equal "admin_burn", redemption.kind
    assert_nil redemption.day_pass_id
    assert_equal @admin.id, redemption.performed_by_id
    assert_equal "walked in on the old system", redemption.guest_name
  end

  test "admin adds a pass back — works even when the pack is at zero" do
    @bundle.update!(passes_remaining: 0)

    post "/api/v1/admin/members/#{@member.id}/restore_bundle_pass", headers: headers

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "restored", body["status"]
    assert_equal 1, body["passes_remaining"]
    assert_equal 1, @bundle.reload.passes_remaining
    assert_equal "admin_restore", @bundle.redemptions.order(:id).last.kind
  end

  test "burn with no active pack is a clean 422" do
    @bundle.update!(passes_remaining: 0)

    post "/api/v1/admin/members/#{@member.id}/burn_bundle_pass", headers: headers

    assert_response :unprocessable_entity
    assert_equal 0, @bundle.reload.passes_remaining
  end

  test "add-back on a full pack is a clean 422" do
    post "/api/v1/admin/members/#{@member.id}/restore_bundle_pass", headers: headers

    assert_response :unprocessable_entity
    assert_equal 5, @bundle.reload.passes_remaining
  end

  test "member show includes bundle_passes_remaining for the admin app" do
    get "/api/v1/admin/members/#{@member.id}", headers: headers

    assert_response :success
    assert_equal 5, JSON.parse(response.body)["bundle_passes_remaining"]
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

  # Error copy: staff-facing alerts show these strings verbatim — they must be
  # sentences, not raw outcomes like "(already_covered)".
  test "double-covering a day returns a human-readable error" do
    post "/api/v1/admin/members/#{@member.id}/schedule_bundle_days",
         params: { dates: [(Date.current + 1).iso8601] }.to_json, headers: headers
    assert_equal 4, @bundle.reload.passes_remaining

    post "/api/v1/admin/members/#{@member.id}/schedule_bundle_days",
         params: { dates: [(Date.current + 1).iso8601] }.to_json, headers: headers

    error = JSON.parse(response.body)["error"]
    assert_match "already has coverage", error
    assert_match "nothing was burned", error
    assert_no_match(/already_covered/, error)
    assert_equal 4, @bundle.reload.passes_remaining
  end

  test "an exhausted bundle returns a human-readable error" do
    ActsAsTenant.with_tenant(@operator) { @bundle.update!(passes_remaining: 0) }

    post "/api/v1/admin/members/#{@member.id}/schedule_bundle_days",
         params: { dates: [(Date.current + 1).iso8601] }.to_json, headers: headers

    error = JSON.parse(response.body)["error"]
    assert_match "no bundle pass available", error
    assert_no_match(/no_bundle/, error)
  end

  test "cancelling a same-day burn returns a human-readable too-late error" do
    tz = ActiveSupport::TimeZone[@location.time_zone.presence || "UTC"]
    today = Time.current.in_time_zone(tz).to_date
    dp = nil
    ActsAsTenant.with_tenant(@operator) do
      dp = Billing::DayPassBundles::ScheduleDay.call(
        user: @member, location: @location, date: today, performed_by: @admin).day_pass
    end

    post "/api/v1/admin/members/#{@member.id}/scheduled_bundle_days/#{dp.id}/cancel", headers: headers

    error = JSON.parse(response.body)["error"]
    assert_match "too late", error
    assert_no_match(/too_late/, error)
    assert_equal 4, @bundle.reload.passes_remaining
  end

  # --- Task 11: office_room on the listing (additive, ADR 0026) -----------

  test "the scheduled-days listing names the office for a Day Office pass" do
    @location.update!(working_day_start: "08:00", working_day_end: "18:00")
    date = Date.current + 2
    ActsAsTenant.with_tenant(@operator) do
      # A second member so the standard bundle from setup doesn't collide.
      @office_member = create(:user, operator: @operator, original_location: @location, current_location: @location)
      make_office_bundle(member: @office_member)
      Billing::DayPassBundles::ScheduleDay.call(user: @office_member, location: @location,
                                                date: date, performed_by: @admin)
    end

    get "/api/v1/admin/members/#{@office_member.id}/scheduled_bundle_days", headers: headers

    assert_response :success
    row = JSON.parse(response.body).first
    assert_equal "Office A", row["office_room"]
    # Shape stays additive — the keys old clients read are untouched.
    assert_equal date.iso8601, row["day"]
    assert row["date"].present?
  end

  test "the scheduled-days listing reports a nil office_room for a standard pass" do
    date = Date.current + 2
    ActsAsTenant.with_tenant(@operator) do
      Billing::DayPassBundles::ScheduleDay.call(user: @member, location: @location,
                                                date: date, performed_by: @admin)
    end

    get "/api/v1/admin/members/#{@member.id}/scheduled_bundle_days", headers: headers

    assert_response :success
    row = JSON.parse(response.body).first
    assert row.key?("office_room"), "the key is always present so clients can read it unconditionally"
    assert_nil row["office_room"]
  end
end
