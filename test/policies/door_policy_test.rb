require "test_helper"

class DoorPolicyTest < PolicyAssertions::Test
  setup do
    setup_initial_user_fixtures
  end

  def test_index
    assert_not_permitted @member, Door
    assert_permit @admin, Door
    assert_permit @community_manager, Door
    assert_permit @general_manager, Door
  end

  def test_show
    assert_not_permitted @member, Door
    assert_permit @admin, Door
    assert_permit @community_manager, Door
    assert_permit @general_manager, Door
  end

  def test_new
    assert_not_permitted @member, Door
    assert_permit @admin, Door
    assert_permit @community_manager, Door
    assert_permit @general_manager, Door
  end

  def test_create
    assert_not_permitted @member, Door
    assert_permit @admin, Door
    assert_permit @community_manager, Door
    assert_permit @general_manager, Door
  end

  def test_update
    assert_not_permitted @member, Door
    assert_permit @admin, Door
    assert_permit @community_manager, Door
    assert_permit @general_manager, Door
  end

  def test_edit
    assert_not_permitted @member, Door
    assert_permit @admin, Door
    assert_permit @community_manager, Door
    assert_permit @general_manager, Door
  end

  def test_destroy
    assert_not_permitted @member, Door
    assert_not_permitted @admin, Door
    assert_not_permitted @community_manager, Door
    assert_not_permitted @general_manager, Door
    assert_permit @superadmin, Door
  end

  def test_open
    assert_permit @member, Door
    assert_permit @admin, Door
    assert_permit @community_manager, Door
    assert_permit @general_manager, Door
  end

  def test_keys
    assert_permit @member, Door
    assert_permit @admin, Door
    assert_permit @community_manager, Door
    assert_permit @general_manager, Door
  end
end
