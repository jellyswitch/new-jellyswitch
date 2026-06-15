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
    assert_not_permitted @community_manager, Room
    assert_permit @general_manager, Room
  end

  def test_create
    assert_not_permitted @member, Room
    assert_permit @admin, Room
    assert_not_permitted @community_manager, Room
    assert_permit @general_manager, Room
  end

  def test_edit
    assert_not_permitted @member, Room
    assert_permit @admin, Room
    assert_not_permitted @community_manager, Room
    assert_permit @general_manager, Room
  end

  def test_update
    assert_not_permitted @member, Room
    assert_permit @admin, Room
    assert_not_permitted @community_manager, Room
    assert_permit @general_manager, Room
  end

  # Regression: Tahoe Longhouse lockout. A freshly-onboarded operator admin has
  # the admin role but no location_managements row (onboarding never creates one),
  # so admin_of_location? was false and updating a room raised
  # Pundit::NotAuthorizedError. An admin with no explicit location scoping should
  # manage their own operator's location(s).
  def test_unscoped_admin_may_manage_rooms
    assert_empty users(:unscoped_admin).managed_location_ids
    assert RoomPolicy.new(@unscoped_admin, Room).update?, "unscoped admin should be allowed to update rooms"
    assert RoomPolicy.new(@unscoped_admin, Room).edit?, "unscoped admin should be allowed to edit rooms"
    assert RoomPolicy.new(@unscoped_admin, Room).create?, "unscoped admin should be allowed to create rooms"
  end

  def test_destroy
    assert_not_permitted @member, Room
    assert_not_permitted @admin, Room
    assert_not_permitted @community_manager, Room
    assert_not_permitted @general_manager, Room
    assert_permit @superadmin, Room
  end
end
