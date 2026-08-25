require "test_helper"

# Pausing was commented out of every web view in October 2022 (2ed4441d) with no
# stated reason, and the system tests were commented out in the same commit. The
# app became the only way to pause — which is how a Tahoe Longhouse member paused
# a Dedicated Desk from their phone and left their belongings behind.
#
# These cover the restored web flow end to end so it can't rot silently again:
# the form renders with the location's warning attached, pausing works, the card
# reflects it, and unpausing works.
class Operator::PauseMembershipWebTest < ActionDispatch::IntegrationTest
  WARNING = "Heads up! If you have belongings stored at a dedicated desk, " \
            "pausing means giving up that desk.".freeze

  setup do
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
    @member   = users(:cowork_tahoe_member)
    # Pausing is gated on billing being live for the operator.
    @operator.update!(billing_state: "production")
    @member.update!(approved: true, current_location: @location, original_location: @location)

    # The member fixture already carries a subscription; the page lists every
    # one of them, so leave only the desk membership under test.
    @member.subscriptions.destroy_all

    ActsAsTenant.with_tenant(@operator) do
      @plan = Plan.create!(
        name: "Dedicated Desk", operator: @operator, location: @location,
        plan_type: "individual", interval: "monthly", amount_in_cents: 30_000,
        available: true, visible: true,
      )
      @subscription = Subscription.create!(
        plan: @plan, subscribable: @member, billable: @member,
        active: true, start_date: 1.month.ago,
        stripe_subscription_id: "sub_test_pause",
      )
    end

    # Rendering the membership card asks Stripe about the live subscription
    # (has_end_date? / has_stripe_subscription?); none of that is what these
    # cover, and a real call would be blocked anyway.
    Subscription.any_instance.stubs(:stripe_subscription).returns(nil)
    Subscription.any_instance.stubs(:has_stripe_subscription?).returns(true)

    log_in @member
  end

  # The interactors talk to Stripe directly; the pause/unpause round trip is
  # what's under test here, not Stripe's response shape.
  def with_stripe_stubbed
    Stripe::Subscription.stub(:update, true) { yield }
  end

  test "the membership page offers to pause, carrying the location's warning" do
    @location.update!(pause_warning: WARNING)

    get user_memberships_path(@member), env: default_env
    assert_response :success
    # pause and unpause share one path and differ only by verb, so match on the
    # submit itself rather than the form's action.
    assert_select "input[type=submit][value=?][data-turbo-confirm=?]",
      "Pause Membership", WARNING
  end

  test "with no warning configured the pause form still works, just unguarded" do
    @location.update!(pause_warning: nil)

    get user_memberships_path(@member), env: default_env
    assert_response :success
    assert_select "input[type=submit][value=?]", "Pause Membership"
    # (The cancel button carries its own confirm, so scope this to the pause one.)
    assert_select "input[value=?][data-turbo-confirm]", "Pause Membership", count: 0
  end

  test "a member can pause from the web" do
    @location.update!(pause_warning: WARNING)

    with_stripe_stubbed do
      post pause_membership_path(@subscription), params: { resumes_at: "30" }, env: default_env
    end

    assert @subscription.reload.paused?, "the subscription should be paused"
    assert FeedItem.where(operator: @operator)
                   .where("blob->>'type' = ?", "membership_paused").exists?,
      "staff must get a feed card when a member pauses"
  end

  test "a paused membership shows as paused and offers unpause as a real form" do
    @subscription.update!(paused: true)

    get user_memberships_path(@member), env: default_env
    assert_response :success
    assert_select "span.badge", text: "Paused"
    # button_to, not link_to + method: :delete — the link variant is downgraded
    # to a plain GET inside the iOS WKWebView wrapper and never fires.
    assert_select "form[action=?] input[name=_method][value=delete]",
      unpause_membership_path(@subscription)
  end

  test "a member can unpause from the web" do
    @subscription.update!(paused: true)

    with_stripe_stubbed do
      delete unpause_membership_path(@subscription), env: default_env
    end

    assert_not @subscription.reload.paused?, "the subscription should be resumed"
  end

  test "a paused membership does not also offer to pause again" do
    @subscription.update!(paused: true)

    get user_memberships_path(@member), env: default_env
    assert_select "input[type=submit][value=?]", "Pause Membership", count: 0
  end
end
