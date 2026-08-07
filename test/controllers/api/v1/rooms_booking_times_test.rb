require "test_helper"

class Api::V1::RoomsBookingTimesTest < ActionDispatch::IntegrationTest
  setup do
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
    @location.update!(working_day_start: "06:00", working_day_end: "20:00")
    @member     = users(:cowork_tahoe_member)
    @non_member = users(:cowork_tahoe_non_member)
    plans(:cowork_tahoe_full_time_plan).update!(location_id: @location.id)
    @date = (Date.current + 7).to_s
  end

  def hours_for(user)
    token = JWT.encode({ user_id: user.id, operator_id: @operator.id, exp: 30.days.from_now.to_i },
                       Rails.application.secret_key_base, "HS256")
    get "/api/v1/rooms/booking_times", params: { date: @date },
        headers: { "Authorization" => "Bearer #{token}", "X-Operator-Subdomain" => @operator.subdomain }
    assert_response :success
    JSON.parse(response.body).fetch("times").map { |t| t["hour"] }
  end

  test "a 24/7 member gets evening start times past the posted close" do
    hours = hours_for(@member)
    assert_includes hours, 21
    assert_equal 23, hours.max
  end

  test "a non-member is bounded by posted working hours" do
    assert hours_for(@non_member).max < 20
  end

end
