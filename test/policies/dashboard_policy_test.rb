require "test_helper"

class DashboardPolicyTest < PolicyAssertions::Test

  setup do
    @admin = users(:cowork_tahoe_admin)
    @member = users(:cowork_tahoe_member)
    @community_manager = users(:cowork_tahoe_community_manager)
    @general_manager = users(:cowork_tahoe_general_manager)
  end

  def test_show
    assert_not_permitted @member, :dashboard
    assert_permit @admin, :dashboard
    assert_not_permitted @community_manager, :dashboard
    assert_not_permitted @general_manager, :dashboard
  end
end