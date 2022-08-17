require 'test_helper'

class FeedItemsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:admin)
    log_in @user
  end

  test "should redirect to onboarding if operator is not yet onboarded" do
    @user.operator.update(skip_onboarding: false)
    get feed_items_path, env: default_env
    assert_redirected_to controller: "operator/onboarding", action: "new"
  end

  test "should render :index without errors" do
    get feed_items_path, env: default_env
    assert_response :success
  end
end
