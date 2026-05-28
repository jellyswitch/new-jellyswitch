require "test_helper"

# When a member pauses their subscription — either immediately or at the
# end of their billing cycle — they must lose building access and the
# member-side room booking allowance. Before this fix all access
# predicates (`has_active_subscription?`, `member?(location)`,
# `has_building_access_membership?`, `allowed_in?`) read
# `subscriptions.active` which does *not* exclude paused rows, so paused
# members kept getting in.
class UserPausedSubscriptionTest < ActiveSupport::TestCase
  setup do
    @member       = users(:cowork_tahoe_member)
    @location     = locations(:cowork_tahoe_location)
    @subscription = subscriptions(:cowork_tahoe_subscription)

    # Sanity: the fixture pre-pause state must grant access, otherwise
    # the test is trivially passing because the user already had no sub.
    @subscription.update!(active: true, paused: false)
    assert @member.has_active_subscription?,            "fixture pre-condition: member should have active sub"
    assert @member.member?(@location),                  "fixture pre-condition: member should be a member at location"
    assert @member.has_active_subscription_at_location?(@location)
  end

  test "pausing the subscription revokes has_active_subscription?" do
    @subscription.update!(paused: true)
    refute @member.has_active_subscription?,
      "paused subscription must not count as active for access purposes"
  end

  test "pausing the subscription revokes member?(location)" do
    @subscription.update!(paused: true)
    refute @member.member?(@location),
      "paused subscription must not count as a membership at this location"
  end

  test "pausing the subscription revokes has_active_subscription_at_location?" do
    @subscription.update!(paused: true)
    refute @member.has_active_subscription_at_location?(@location)
  end

  test "active_subscription_for_location returns nil for a paused sub" do
    @subscription.update!(paused: true)
    assert_nil @member.active_subscription_for_location(@location),
      "paused sub must not feed the free-meeting-minutes allowance into room booking"
  end

  # Unpausing has to put everything back — otherwise resuming a
  # membership wouldn't restore door + room access either.
  test "unpausing restores access" do
    @subscription.update!(paused: true)
    refute @member.has_active_subscription?

    @subscription.update!(paused: false)
    assert @member.has_active_subscription?
    assert @member.member?(@location)
  end
end
