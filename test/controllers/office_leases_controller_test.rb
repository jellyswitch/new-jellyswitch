require 'test_helper'

class SubscriptionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:cowork_tahoe_member)
    @office_lease_plan = office_leases(:office_23b_lease)
    log_in @user
  end

  test "should cancel office lease now to operator" do
    delete destroy_office_lease_now_path(@office_lease_plan), headers: { "HTTP_REFERER": "http://www.example.com/office_leases/#{@office_lease_plan.id}" }, env: default_env
      
    assert_redirected_to office_lease_path(@office_lease_plan)
  end

end