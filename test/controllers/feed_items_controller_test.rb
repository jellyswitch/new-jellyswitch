require 'test_helper'

class FeedItemsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:cowork_tahoe_admin)
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

  test "should create a new feed item and redirect back to index (web)" do
    post feed_items_path( params: { feed_item: { text: "This is a management note" } }), env: default_env
    assert_redirected_to controller: "operator/feed_items", action: "index"
  end

  test "should create a new feed item and redirect back to index (iOS)" do
    post feed_items_path( params: { feed_item: { text: "This is a management note" } }), env: ios_env
    assert_redirected_to controller: "operator/feed_items", action: "index"
  end
end
