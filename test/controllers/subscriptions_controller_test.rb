require 'test_helper'

class SubscriptionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:cowork_tahoe_member)
    @subscription = subscriptions(:cowork_tahoe_subscription)
    @part_time_plan = plans(:cowork_tahoe_part_time_plan)
    @full_time_plan = plans(:cowork_tahoe_full_time_plan)
    log_in @user
    StripeMock.start
    setup_stripe
    stub_request(:post, "https://fcm.googleapis.com/fcm/send")
      .to_return(
        status: 200
      )
  end

  teardown do
    WebMock.reset!
  end

  test "should subscribe to operator" do
    post subscriptions_path, params: { subscription: { plan: @part_time_plan.id } }, headers: { "HTTP_REFERER": "http://www.example.com/home" }, env: default_env
    assert_redirected_to controller: "operator/landing", action: "home"
  end

  test "should set subscription to cancel to operator" do
    delete subscription_path(@subscription), headers: { "HTTP_REFERER": "http://www.example.com/users/#{@user.slug}/memberships" }, env: default_env do
      post feed_items_path( params: { feed_item: { text: "user canceled their membership" } }), env: default_env
    end
    assert_redirected_to user_memberships_path(@user)
  end

  test "should cancel subscription now to operator" do
    delete destroy_subscription_now_path(@subscription), headers: { "HTTP_REFERER": "http://www.example.com/users/#{@user.slug}/memberships" }, env: default_env do
      post feed_items_path( params: { feed_item: { text: "user canceled their membership" } }), env: default_env
    end
    assert_redirected_to user_memberships_path(@user)
  end

  test "should get edit subscription page" do
    get edit_subscription_path(@subscription), env: default_env
    assert_response :ok
  end

  test "should update plan" do
    patch subscription_path(@subscription), params: { subscription: { plan_id: @full_time_plan.id } }, env: default_env
    assert_response :redirect
  end

  test "cancel subscription failure should keep subscription acive and not post a feed item" do
    delete subscription_path(@subscription), params: { subscription: { plan: "foobar" } }, env: default_env
    assert_response :redirect
  end

  # The Cancel Membership CTA must render as a button_to form (POST +
  # _method=delete hidden field), not a link_to with data-turbo-method=delete.
  # The link variant has been getting routed as a plain GET through the iOS
  # WKWebView wrapper's navigation interception — which after PR #452 lands
  # at the new #show redirect, silently redirects to change_account, and
  # never actually cancels. A real <form method="post"> survives every
  # interception layer (Turbo Drive JS, Turbo Native, plain WKWebView).
  test "cancel CTA on memberships page is a form submission, not a data-turbo-method link" do
    get user_memberships_path(@user), env: default_env
    assert_response :ok

    # The page should include a form whose action is the subscription path
    # and which carries the _method=delete override.
    assert_select "form[action='#{subscription_path(@subscription)}'][method='post']" do
      assert_select "input[type='hidden'][name='_method'][value='delete']", count: 1
    end

    # And it must NOT use the old link_to + data-turbo-method=delete shape
    # for that same destination, since that's what was breaking in the
    # wrapper. (We allow data-turbo-method elsewhere on the page — only the
    # subscription DELETE link is the regression target.)
    assert_select "a[href='#{subscription_path(@subscription)}'][data-turbo-method='delete']", count: 0
  end

  # PATCH /subscriptions/:id used to bubble Stripe::InvalidRequestError
  # ("Cannot update a subscription whose status is paused") as a 500
  # when a paused member tried to switch plans. Now we short-circuit
  # with a friendly flash before SwitchMembership talks to Stripe.
  test "update on a paused subscription redirects with a friendly unpause-first message" do
    @subscription.update!(paused: true)
    patch subscription_path(@subscription),
          params: { subscription: { plan_id: @full_time_plan.id } },
          headers: { "HTTP_REFERER": "http://www.example.com/users/#{@user.slug}/memberships" },
          env: default_env

    assert_response :redirect
    assert_match(/paused.*unpause/i, flash[:error] || "",
      "expected an actionable 'unpause first' message instead of a 500")
    assert @subscription.reload.paused?, "the paused sub must stay paused"
  end
end
