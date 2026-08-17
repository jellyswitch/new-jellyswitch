require "test_helper"

# Nothing used to stop a subscribable from holding two active memberships, so a
# member who fired a second "Subscribe" while the first was still in flight got
# two Stripe subscriptions and two charges a month (Aaron Squier, 2026-06-24).
# Switching plans is a separate path — SwitchMembership reuses the one Stripe
# subscription — and must stay unaffected.
class Billing::Subscription::DuplicateMembershipGuardTest < ActiveSupport::TestCase
  setup do
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
    ActsAsTenant.with_tenant(@operator) do
      @member = create(:user, operator: @operator, original_location: @location, current_location: @location)
      @flex = Plan.create!(operator: @operator, location: @location, name: "Flex", plan_type: "individual",
                           amount_in_cents: 22_500, interval: "month", available: true, visible: true)
      @full = Plan.create!(operator: @operator, location: @location, name: "Full Time", plan_type: "individual",
                           amount_in_cents: 30_000, interval: "month", available: true, visible: true)
      @lease_plan = Plan.create!(operator: @operator, location: @location, name: "Office Lease", plan_type: "lease",
                                 amount_in_cents: 90_000, interval: "month", available: true, visible: true)
    end
  end

  def existing_membership(plan: @flex)
    Subscription.create!(plan: plan, subscribable: @member, billable: @member,
                         active: true, start_date: Date.current)
  end

  def new_subscription(plan)
    Subscription.new(plan: plan, subscribable: @member)
  end

  test "flags a second active membership" do
    existing_membership

    assert new_subscription(@full).duplicate_active_membership?
  end

  test "flags a second membership on the same plan" do
    existing_membership(plan: @flex)

    assert new_subscription(@flex).duplicate_active_membership?
  end

  test "allows the first membership" do
    assert_not new_subscription(@flex).duplicate_active_membership?
  end

  test "an ended membership does not block a new one" do
    existing_membership.update!(active: false)

    assert_not new_subscription(@full).duplicate_active_membership?
  end

  # An org renting three offices legitimately holds three lease subscriptions —
  # prod has several. Leases are excluded from both sides of the check.
  test "office leases neither block nor are blocked" do
    existing_membership(plan: @lease_plan)

    assert_not new_subscription(@lease_plan).duplicate_active_membership?,
               "a second lease must be allowed"
    assert_not new_subscription(@full).duplicate_active_membership?,
               "a lease must not block a membership"
  end

  test "a membership does not block a lease" do
    existing_membership(plan: @flex)

    assert_not new_subscription(@lease_plan).duplicate_active_membership?
  end

  # The exact shape of the Aaron Squier incident, through the real interactor.
  test "SaveSubscription refuses the duplicate and says why" do
    existing_membership
    @member.stubs(:card_added_for_location?).returns(true)

    result = Billing::Subscription::SaveSubscription.call(
      subscription: new_subscription(@full),
      user: @member,
      location: @location,
      start_day: Date.current,
    )

    assert result.failure?
    assert_equal Subscription::DUPLICATE_MEMBERSHIP_MESSAGE, result.message
    assert_equal 1, Subscription.memberships.active.where(subscribable: @member).count
  end

  test "SaveSubscription still creates the first membership" do
    @member.stubs(:card_added_for_location?).returns(true)

    result = Billing::Subscription::SaveSubscription.call(
      subscription: new_subscription(@flex),
      user: @member,
      location: @location,
      start_day: Date.current,
    )

    assert result.success?, result.message
    assert_equal 1, Subscription.memberships.active.where(subscribable: @member).count
  end

  test "CreatePendingSubscription refuses a duplicate too" do
    existing_membership
    @member.stubs(:card_added_for_location?).returns(true)

    result = Billing::Subscription::CreatePendingSubscription.call(
      subscription: new_subscription(@full),
      user: @member,
      location: @location,
      start_day: Date.current,
    )

    assert result.failure?
    assert_equal Subscription::DUPLICATE_MEMBERSHIP_MESSAGE, result.message
  end

  # The guard keys on the subscribable, so one member's membership must not
  # block another's.
  test "another member's membership is irrelevant" do
    existing_membership
    other = ActsAsTenant.with_tenant(@operator) do
      create(:user, operator: @operator, original_location: @location, current_location: @location)
    end

    assert_not Subscription.new(plan: @full, subscribable: other).duplicate_active_membership?
  end
end
