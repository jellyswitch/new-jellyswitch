require "test_helper"

class Billing::DayPasses::SaveDayPassTest < ActiveSupport::TestCase
  def setup
    @user = users(:cowork_tahoe_member)
    @day_pass_type = day_pass_type(:cowork_tahoe_day_pass_type)
    @operator = operators(:cowork_tahoe)

    @params = {
      day_pass_type: @day_pass_type.id,
      operator_id: @operator.id,
      day: Date.today,
    # Add other required params here
    }
  end

  test "should create a day pass for a valid user" do
    assert_difference "DayPass.count", 1 do
      assert_difference "BillableFactory.for(DayPass.last).billable.day_passes.count", 1 do
        assert_nothing_raised do
          Billing::DayPasses::SaveDayPass.call(
            day_pass: nil,
            token: nil,
            operator: nil,
            out_of_band: nil,
            params: @params,
            user_id: @user.id,
          )
        end
      end
    end
  end

  test "should fail to create a day pass for an invalid user" do
    assert_no_difference "DayPass.count" do
      result = Billing::DayPasses::SaveDayPass.call(
        day_pass: nil,
        token: nil,
        operator: nil,
        out_of_band: nil,
        params: @params,
        user_id: -1,
      )

      assert result.failure?
      assert_equal "No such user with ID -1", result.message
    end
  end

  def teardown
    DayPass.destroy_all
  end
end
