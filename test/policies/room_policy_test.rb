require "test_helper"

class RoomPolicyTest < PolicyAssertions::Test
  setup do
    setup_initial_user_fixtures
  end

  def test_show
    assert_permit @member, rooms(:small_meeting_room)
    assert_permit @admin, rooms(:small_meeting_room)
    assert_permit @community_manager, rooms(:small_meeting_room)
    assert_permit @general_manager, rooms(:small_meeting_room)
  end

  def test_new
    assert_not_permitted @member, Room
    assert_permit @admin, Room
    assert_permit @community_manager, Room
    assert_permit @general_manager, Room
  end

  def test_create
    assert_not_permitted @member, Room
    assert_permit @admin, Room
    assert_permit @community_manager, Room
    assert_permit @general_manager, Room
  end

  def test_edit
    assert_not_permitted @member, Room
    assert_permit @admin, Room
    assert_permit @community_manager, Room
    assert_permit @general_manager, Room
  end

  def test_update
    assert_not_permitted @member, Room
    assert_permit @admin, Room
    assert_permit @community_manager, Room
    assert_permit @general_manager, Room
  end

  def test_destroy
    assert_not_permitted @member, Room
    assert_permit @admin, Room
    assert_permit @community_manager, Room
    assert_permit @general_manager, Room
  end
end
