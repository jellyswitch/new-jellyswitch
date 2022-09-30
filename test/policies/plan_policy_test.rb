require "test_helper"

class PlanPolicyTest < PolicyAssertions::Test

  setup do
    setup_initial_user_fixtures
  end

  def test_index
    assert_not_permitted @member, Plan
    assert_permit @admin, Plan
    assert_permit @community_manager, Plan
    assert_permit @general_manager, Plan
  end

  def test_archived
    assert_not_permitted @member, Plan
    assert_permit @admin, Plan
    assert_permit @community_manager, Plan
    assert_permit @general_manager, Plan
  end

  def test_show
    assert_not_permitted @member, Plan
    assert_permit @admin, Plan
    assert_permit @community_manager, Plan
    assert_permit @general_manager, Plan
  end

  def test_edit
    assert_not_permitted @member, Plan
    assert_permit @admin, Plan
    assert_permit @community_manager, Plan
    assert_permit @general_manager, Plan
  end

  def test_new
    assert_not_permitted @member, Plan
    assert_permit @admin, Plan
    assert_permit @community_manager, Plan
    assert_permit @general_manager, Plan
  end

  def test_create
    assert_not_permitted @member, Plan
    assert_permit @admin, Plan
    assert_permit @community_manager, Plan
    assert_permit @general_manager, Plan
  end

  def test_update
    assert_not_permitted @member, Plan
    assert_permit @admin, Plan
    assert_permit @community_manager, Plan
    assert_permit @general_manager, Plan
  end

  def test_destroy
    assert_not_permitted @member, Plan
    assert_permit @admin, Plan
    assert_permit @community_manager, Plan
    assert_permit @general_manager, Plan
  end

  def test_unarchive
    assert_not_permitted @member, Plan
    assert_permit @admin, Plan
    assert_permit @community_manager, Plan
    assert_permit @general_manager, Plan
  end

  def test_toggle_visibility
    assert_not_permitted @member, Plan
    assert_permit @admin, Plan
    assert_permit @community_manager, Plan
    assert_permit @general_manager, Plan
  end

  def test_toggle_availability
    assert_not_permitted @member, Plan
    assert_permit @admin, Plan
    assert_permit @community_manager, Plan
    assert_permit @general_manager, Plan
  end

  def test_toggle_building_access
    assert_not_permitted @member, Plan
    assert_permit @admin, Plan
    assert_permit @community_manager, Plan
    assert_permit @general_manager, Plan
  end
end