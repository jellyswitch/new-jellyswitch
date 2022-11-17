require "test_helper"

class SubscriptionPolicyTest < PolicyAssertions::Test

  setup do
    setup_initial_user_fixtures
  end

  def test_edit
    assert_permit @member, subscriptions(:cowork_tahoe_subscription)
    assert_permit @admin, subscriptions(:cowork_tahoe_subscription)
    assert_permit @community_manager, subscriptions(:cowork_tahoe_subscription)
    assert_permit @general_manager, subscriptions(:cowork_tahoe_subscription)
  end

  def test_update
    assert_permit @member, subscriptions(:cowork_tahoe_subscription)
    assert_permit @admin, subscriptions(:cowork_tahoe_subscription)
    assert_permit @community_manager, subscriptions(:cowork_tahoe_subscription)
    assert_permit @general_manager, subscriptions(:cowork_tahoe_subscription)
  end

  def test_destroy
    assert_permit @member, subscriptions(:cowork_tahoe_subscription)
    assert_permit @admin, subscriptions(:cowork_tahoe_subscription)
    assert_permit @community_manager, subscriptions(:cowork_tahoe_subscription)
    assert_permit @general_manager, subscriptions(:cowork_tahoe_subscription)
  end
end