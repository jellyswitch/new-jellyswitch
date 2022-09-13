require "test_helper"

class WeeklyUpdatePolicyTest < PolicyAssertions::Test

  setup do
    setup_initial_user_fixtures
  end

  def test_index
    assert_not_permitted @member, WeeklyUpdate
    assert_permit @admin, WeeklyUpdate
    assert_permit @community_manager, WeeklyUpdate
    assert_permit @general_manager, WeeklyUpdate
  end

  def test_create
    assert_not_permitted @member, WeeklyUpdate
    assert_permit @admin, WeeklyUpdate
    assert_permit @community_manager, WeeklyUpdate
    assert_permit @general_manager, WeeklyUpdate
  end

  def test_show
    assert_not_permitted @member, WeeklyUpdate
    assert_permit @admin, WeeklyUpdate
    assert_permit @community_manager, WeeklyUpdate
    assert_permit @general_manager, WeeklyUpdate
  end
end