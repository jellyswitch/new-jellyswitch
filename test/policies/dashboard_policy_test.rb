require "test_helper"

class DashboardPolicyTest < PolicyAssertions::Test

  setup do
    setup_initial_user_fixtures
  end

  def test_show
    assert_not_permitted @member, :dashboard
    assert_permit @admin, :dashboard
    assert_not_permitted @community_manager, :dashboard
    assert_permit @general_manager, :dashboard
  end
end