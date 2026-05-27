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
    get subscription_path(@subscription), env: default_env
    assert_response :redirect
    assert_nil flash[:alert], "anonymous preview must not trigger the Whoops flash"
  end
end
