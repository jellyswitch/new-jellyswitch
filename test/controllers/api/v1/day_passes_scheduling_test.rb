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

  # ScheduleDays holds one transaction (and a bundle row lock) open across the
  # whole batch, so an unbounded list is an unbounded lock hold on rows the door
  # path needs. Refused before any DB work.
  test "POST schedule refuses more than 30 dates and burns nothing" do
    dates = (1..31).map { |n| (Date.current + n).iso8601 }

    post "/api/v1/day_passes/schedule", params: { dates: dates }.to_json, headers: headers(@member)

    assert_response :unprocessable_entity
    assert_equal "You can schedule up to 30 days at a time.", JSON.parse(response.body)["error"]
    assert_equal 5, @bundle.reload.passes_remaining
    assert_equal 0, @member.day_passes.count
  end

  test "POST schedule accepts exactly 30 dates" do
    ActsAsTenant.with_tenant(@operator) { @bundle.update!(passes_remaining: 30, quantity_purchased: 30) }
    dates = (1..30).map { |n| (Date.current + n).iso8601 }

    post "/api/v1/day_passes/schedule", params: { dates: dates }.to_json, headers: headers(@member)

    assert_response :success
    assert_equal 30, JSON.parse(response.body)["scheduled_days"].size
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

  # Regression: failed_date was stored as a raw String → calling .strftime on it
  # blew up with NoMethodError (500). The fix is to coerce to Date in ScheduleDays.
  test "already_covered returns a clean client error, not 500" do
    future_date = (Date.current + 5).iso8601
    # Schedule the date once so the member is already covered for it.
    ActsAsTenant.with_tenant(@operator) do
      Billing::DayPassBundles::ScheduleDay.call(
        user: @member, location: @location, date: future_date, performed_by: @member)
    end
    # Attempt to schedule the same date again.
    post "/api/v1/day_passes/schedule",
         params: { dates: [future_date] }.to_json,
         headers: headers(@member)
    assert_response :unprocessable_entity
    body = JSON.parse(response.body)
    assert body["error"].present?, "expected an error message in response"
  end

  # :too_late negative path — a bundle pass dated today cannot be cancelled.
  test "cancel_scheduled on a same-day pass returns a client error" do
    dp = nil
    ActsAsTenant.with_tenant(@operator) do
      # Create a bundle-sourced DayPass for today directly (ScheduleDay's future-only
      # guard prevents scheduling today via the API, so we insert at DB level).
      dp = DayPass.create!(
        user: @member, billable: @member,
        operator: @operator, location: @location,
        day_pass_type: @bundle.day_pass_type,
        day: Date.current, imported: true
      )
      # Attach a redemption so CancelScheduledDay can locate the bundle.
      DayPassBundleRedemption.create!(
        day_pass_bundle: @bundle, operator: @operator,
        day_pass: dp, kind: "entry",
        performed_by: @member, redeemed_at: Time.current
      )
      @bundle.update!(passes_remaining: @bundle.passes_remaining - 1)
    end
    post "/api/v1/day_passes/#{dp.id}/cancel_scheduled", headers: headers(@member)
    assert_response :unprocessable_entity
    body = JSON.parse(response.body)
    assert body["error"].present?, "expected an error message for too_late"
    # The pass must remain intact.
    assert DayPass.exists?(dp.id), "day pass should not have been destroyed"
  end

  test "POST schedule returns 422 when a requested day is at the type's daily limit" do
    ActsAsTenant.with_tenant(@operator) do
      @bundle.day_pass_type.update!(daily_limit: 1)
      other = create(:user, operator: @operator, original_location: @location, current_location: @location)
      DayPass.create!(user: other, billable: other, operator: @operator, location: @location,
                      day_pass_type: @bundle.day_pass_type, day: Date.current + 1, imported: true)
    end

    post "/api/v1/day_passes/schedule",
         params: { dates: [(Date.current + 1).iso8601] }.to_json, headers: headers(@member)

    assert_response :unprocessable_entity
    assert_includes JSON.parse(response.body)["error"], "fully booked"
    assert_equal 5, @bundle.reload.passes_remaining
  end

  # Task 10 / ADR 0026: a sold-out Day Office bundle gets the same structured,
  # machine-readable payload #create uses (fallback CTA) — scheduling a future
  # office day from the calendar is an acquisition flow like purchase, unlike
  # #reschedule which stays a plain refusal.
  test "POST schedule returns the structured sold-out payload for a Day Office bundle" do
    date = Date.current + 1
    office_member = nil
    room_a = room_b = nil
    ActsAsTenant.with_tenant(@operator) do
      # A dedicated member (not @member/@bundle from setup): eligible_bundle
      # picks the SOONEST-EXPIRING bundle, tie-broken oldest-first, so a fresh
      # office bundle for @member would lose to setup's older standard 5-Pack.
      office_member = create(:user, operator: @operator, original_location: @location, current_location: @location)
      _bundle, room_a, room_b = make_office_bundle(member: office_member)
      fill_office_pool!(date, room_a, room_b)
    end

    post "/api/v1/day_passes/schedule",
         params: { dates: [date.iso8601] }.to_json, headers: headers(office_member)

    assert_response :unprocessable_entity
    body = JSON.parse(response.body)
    assert_equal "day_office_sold_out", body["code"]
    assert_includes body["error"], "fully booked"
    assert body.key?("fallback_day_pass_type")
  end
end
