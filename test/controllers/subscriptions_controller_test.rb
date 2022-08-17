require 'test_helper'

class SubscriptionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:customer_one)
    log_in @user
  end

  test "assigns plan to user with :create" do
    post subscriptions_path, params: { plan: plans(:plan_one) }, env: ios_env
    assert_response :success
  end
end
