require "test_helper"

class Api::V1::ReservationsCoverageTest < ActionDispatch::IntegrationTest
  setup do
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
    ActsAsTenant.with_tenant(@operator) do
      # Room Credits are orthogonal to day-pass coverage — disable so ChargeCredits
      # doesn't 422 ("Insufficient credit balance") before the coverage steps run.
      @location.update!(credits_enabled: false) if @location.respond_to?(:credits_enabled)
      @member = create(:user, operator: @operator, original_location: @location, current_location: @location)
      @room = create(:room, operator: @operator, location: @location, hourly_rate_in_cents: 0, include_with_day_pass: true)
      @type = create(:day_pass_type, operator: @operator, location: @location,
                     included_meeting_room_minutes: 120, amount_in_cents: 4000, available: true, visible: true,
                     default_for_room_booking: true)
    end
  end

  def headers(user)
    token = JWT.encode({ user_id: user.id, exp: 30.days.from_now.to_i }, Rails.application.secret_key_base, "HS256")
    { "Authorization" => "Bearer #{token}", "X-Operator-Subdomain" => @operator.subdomain, "Content-Type" => "application/json" }
  end

  def body(extra = {})
    {
      reservation: {
        room_id: @room.id,
        # in_time_zone (app zone), NOT to_time (system zone): on a UTC CI
        # runner to_time makes this 9 AM UTC = 2 AM Pacific, which the
        # posted-hours backstop (EnforcePostedHours) correctly rejects.
        datetime_in: (Date.current + 3).in_time_zone.change(hour: 9).iso8601,
        minutes: 60,
      }.merge(extra),
    }.to_json
  end

  test "included room with NO coverage decision is blocked (422), no silent auto-buy" do
    assert_no_difference -> { @member.day_passes.count } do
      post "/api/v1/reservations", params: body, headers: headers(@member)
    end
    assert_response :unprocessable_entity
    assert_equal 0, Reservation.where(user: @member, cancelled: false).count
  end

  test "use_bundle_pass burns a bundle pass and books it" do
    ActsAsTenant.with_tenant(@operator) do
      DayPassBundle.create!(user: @member, operator: @operator, location: @location, day_pass_type: @type,
                            quantity_purchased: 5, passes_remaining: 5, purchased_at: Time.current)
    end
    post "/api/v1/reservations", params: body(use_bundle_pass: true), headers: headers(@member)
    assert_response :created
    res = Reservation.where(user: @member).order(:id).last
    dp = @member.day_passes.for_day(Date.current + 3).first
    assert dp, "a bundle-minted day pass covers the reservation date"
    assert_equal res.id, dp.reservation_id
    assert_equal 4, @member.day_pass_bundles.first.reload.passes_remaining
  end
end
