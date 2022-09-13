require "test_helper"

class ModulePolicyTest < PolicyAssertions::Test

  setup do
    setup_initial_user_fixtures
  end

  def test_index
    assert_not_permitted @member, Module
    assert_permit @admin, Module
    assert_permit @community_manager, Module
    assert_permit @general_manager, Module
    assert_permit @superadmin, Module
  end

  def test_announcements
    assert_not_permitted @member, Module
    assert_permit @admin, Module
    assert_permit @community_manager, Module
    assert_permit @general_manager, Module
    assert_permit @superadmin, Module
  end

  def test_bulletin_board
    assert_not_permitted @member, Module
    assert_permit @admin, Module
    assert_permit @community_manager, Module
    assert_permit @general_manager, Module
    assert_permit @superadmin, Module
  end

  def test_events
    assert_not_permitted @member, Module
    assert_permit @admin, Module
    assert_permit @community_manager, Module
    assert_permit @general_manager, Module
    assert_permit @superadmin, Module
  end

  def test_door_integration
    assert_not_permitted @member, Module
    assert_permit @admin, Module
    assert_permit @community_manager, Module
    assert_permit @general_manager, Module
    assert_permit @superadmin, Module
  end

  def test_rooms
    assert_not_permitted @member, Module
    assert_permit @admin, Module
    assert_permit @community_manager, Module
    assert_permit @general_manager, Module
    assert_permit @superadmin, Module
  end

  def test_offices
    assert_not_permitted @member, Module
    assert_permit @admin, Module
    assert_permit @community_manager, Module
    assert_permit @general_manager, Module
    assert_permit @superadmin, Module
  end

  def test_credits
    assert_not_permitted @member, Module
    assert_permit @admin, Module
    assert_permit @community_manager, Module
    assert_permit @general_manager, Module
    assert_permit @superadmin, Module
  end

  def test_crm
    assert_not_permitted @member, Module
    assert_permit @admin, Module
    assert_permit @community_manager, Module
    assert_permit @general_manager, Module
    assert_permit @superadmin, Module
  end

  def test_childcare
    assert_not_permitted @member, Module
    assert_permit @admin, Module
    assert_permit @community_manager, Module
    assert_permit @general_manager, Module
    assert_permit @superadmin, Module
  end

  def test_reservation_credits_settings
    assert_not_permitted @member, Module
    assert_permit @admin, Module
    assert_permit @community_manager, Module
    assert_permit @general_manager, Module
    assert_permit @superadmin, Module
  end
end