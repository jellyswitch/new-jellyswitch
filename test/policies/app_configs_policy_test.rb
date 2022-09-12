require "test_helper"

class AppConfigsPolicyTest < PolicyAssertions::Test

  setup do
    @admin = users(:cowork_tahoe_admin)
    @member = users(:cowork_tahoe_member)
    @community_manager = users(:cowork_tahoe_community_manager)
    @general_manager = users(:cowork_tahoe_general_manager)
    @superadmin = users(:cowork_tahoe_superadmin)
  end

  def test_index
    assert_not_permitted @member, :app_configs
    assert_not_permitted @admin, :app_configs
    assert_not_permitted @community_manager, :app_configs
    assert_not_permitted @general_manager, :app_configs
    assert_permit @superadmin, :app_configs
  end
end