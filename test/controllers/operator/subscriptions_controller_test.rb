require "test_helper"

# Coverage for GET /subscriptions/:id. The route exists because
# `resources :subscriptions` declares the full CRUD set; the controller
# previously had no `show` action, so any GET to /subscriptions/:id raised
# ActionNotFound → Rails 404. iOS WKWebView's link-preview behavior in the
# mobile app surfaced this for a real member trying to cancel their
# membership.
class Operator::SubscriptionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    setup_initial_user_fixtures
    @subscription = subscriptions(:cowork_tahoe_subscription)
  end

  test "show redirects subscribable to their change-account page" do
    user = @subscription.subscribable
    log_in user
    get subscription_path(@subscription), env: default_env
    assert_redirected_to user_change_account_path(user)
  end

  test "show redirects an admin who follows the same link" do
    log_in @admin.user
    get subscription_path(@subscription), env: default_env
    assert_redirected_to user_change_account_path(@subscription.subscribable)
  end

  # iOS WKWebView's link-preview fetches a GET against the raw href before
  # data-turbo-method=delete intercepts. That request usually carries no
  # session cookies, so Pundit denied access, set the global "Whoops!
  # That's not allowed" flash, and bounced to root — and the flash then
  # bled into the member's next page load, making the cancel flow look
  # broken even though a real tap still worked.
  test "show does not surface the Pundit Whoops flash to anonymous link previews" do
    ActsAsTenant.default_tenant = operators(:cowork_tahoe)
    get subscription_path(@subscription), env: default_env
    assert_response :redirect
    assert_nil flash[:alert], "anonymous preview must not trigger the Whoops flash"
  end

  # Same iOS link-preview blast radius hits the "Change membership" link,
  # which targets /subscriptions/:id/edit. The Pundit denial flash bleeds
  # into the next authenticated page load the same way — so the global
  # ApplicationController#user_not_authorized fix has to cover this too,
  # not just the show route.
  test "edit does not surface the Pundit Whoops flash to anonymous link previews" do
    ActsAsTenant.default_tenant = operators(:cowork_tahoe)
    get edit_subscription_path(@subscription), env: default_env
    assert_response :redirect
    assert_nil flash[:alert], "anonymous preview must not trigger the Whoops flash"
  end

  # A committed member cancelling on the web hits honor_commitment_for_member,
  # which bypasses both cancellation organizers — it must still send the
  # written confirmation email stating billing continues to the boundary.
  test "web cancel of a committed subscription schedules at the boundary and emails a confirmation" do
    member = @subscription.subscribable
    @subscription.plan.update!(interval: "monthly", commitment_interval: 6)
    @subscription.update!(start_date: 2.months.ago.to_date, cancelling_at_end_of_billing_period: false)

    log_in member
    assert_enqueued_emails 1 do
      delete subscription_path(@subscription), env: default_env
    end

    assert_response :redirect
    assert_match(/committed through/i, flash[:notice].to_s)
    assert @subscription.reload.cancelling_at_end_of_billing_period
    assert @subscription.active?, "committed sub stays active until the boundary"
  end

  # A real signed-in user who genuinely lacks permission (here: a different
  # CT member trying to edit someone else's subscription) SHOULD still see
  # the Whoops flash — that's the legitimate use of the rescue. Make sure
  # the global fix didn't accidentally silence that path too.
  test "edit surfaces the Pundit Whoops flash for a logged-in but unauthorized user" do
    log_in users(:cowork_tahoe_community_manager)
    get edit_subscription_path(@subscription), env: default_env
    assert_response :redirect
    assert_equal "Whoops! That's not allowed. If this isn't what you were expecting, please contact our staff.",
                 flash[:alert]
  end
end
