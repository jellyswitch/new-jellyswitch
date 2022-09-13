require "test_helper"

class DoorPunchPolicyTest < PolicyAssertions::Test

  setup do
    setup_initial_user_fixtures
  end

  def test_show
    assert_not_permitted @member, DoorPunch
    assert_permit @admin, DoorPunch
    assert_permit @community_manager, DoorPunch
    assert_permit @general_manager, DoorPunch
  end
end