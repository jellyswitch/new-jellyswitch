require "test_helper"

class AppConfigsPolicyTest < PolicyAssertions::Test

  setup do
    setup_initial_user_fixtures
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