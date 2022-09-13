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

  def new?
    assert_not_permitted @member, Door
    assert_permit @admin, Door
    assert_permit @community_manager, Door
    assert_permit @general_manager, Door
  end

  def create?
    assert_not_permitted @member, Door
    assert_permit @admin, Door
    assert_permit @community_manager, Door
    assert_permit @general_manager, Door
  end

  def update?
    assert_not_permitted @member, Door
    assert_permit @admin, Door
    assert_permit @community_manager, Door
    assert_permit @general_manager, Door
  end

  def edit?
    assert_not_permitted @member, Door
    assert_permit @admin, Door
    assert_permit @community_manager, Door
    assert_permit @general_manager, Door
  end

  def open?
    assert_permit @member, Door
    assert_permit @admin, Door
    assert_permit @community_manager, Door
    assert_permit @general_manager, Door
  end

  def keys?
    assert_permit @member, Door
    assert_permit @admin, Door
    assert_permit @community_manager, Door
    assert_permit @general_manager, Door
  end
end