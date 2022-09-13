require "test_helper"

class MemberGroupPolicyTest < PolicyAssertions::Test

  setup do
    setup_initial_user_fixtures
  end

  def test_show
    assert_not_permitted @member, :member_group
    assert_permit @admin, :member_group
    assert_permit @community_manager, :member_group
    assert_permit @general_manager, :member_group
  end
end