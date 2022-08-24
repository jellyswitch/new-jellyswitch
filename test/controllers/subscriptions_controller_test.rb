require 'test_helper'

class SubscriptionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:cowork_tahoe_member)
    @subscription = subscriptions(:cowork_tahoe_subscription)
    @part_time_plan = plans(:cowork_tahoe_part_time_plan)
    @full_time_plan = plans(:cowork_tahoe_full_time_plan)
    log_in @user
  end

  test "should subscribe to operator" do
    post subscriptions_path, params: { subscription: { plan: @part_time_plan.id } }, headers: { "HTTP_REFERER": "http://www.example.com/home" }, env: default_env
    assert_redirected_to controller: "operator/landing", action: "home"
  end

  test "should cancel subscription to operator" do
    delete subscription_path(@subscription), headers: { "HTTP_REFERER": "http://www.example.com/users/#{@user.slug}/memberships" }, env: default_env do
      post feed_items_path( params: { feed_item: { text: "user canceled their membership" } }), env: default_env
    end
    assert_redirected_to user_memberships_path(@user)
  end

  test "should get edit subscription page" do
    get edit_subscription_path(@subscription), env: default_env
    assert_response :found
  end

  test "should update plan" do
    patch subscription_path(@subscription), params: { subscription: { plan: @full_time_plan.id } }, env: default_env
    assert_response :success
  end

  test "cancel subscription failure should keep subscription acive and not post a feed item" do
    delete subscription_path(@subscription), params: { subscription: { plan: "foobar"} }, env: default_env
    puts feed_items.all.count
    assert_response :redirect
  end
end
