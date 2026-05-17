require "test_helper"

class OperatorDollarsTest < ActiveSupport::TestCase
  test "Operator#day_pass_cost reads dollars from day_pass_cost_in_cents" do
    operator = operators(:cowork_tahoe)
    operator.update!(day_pass_cost_in_cents: 2500)
    assert_in_delta 25.00, operator.day_pass_cost, 0.0001
  end

  test "Operator#day_pass_cost= writes dollars to day_pass_cost_in_cents" do
    operator = operators(:cowork_tahoe)
    operator.day_pass_cost = "40.99"
    assert_equal 4099, operator.day_pass_cost_in_cents
  end

  test "Location responds to dollars accessors" do
    location = locations(:cowork_tahoe_location)
    assert_respond_to location, :hourly_rate
    assert_respond_to location, :hourly_rate=
    assert_respond_to location, :credit_cost
    assert_respond_to location, :childcare_reservation_cost
  end
end
