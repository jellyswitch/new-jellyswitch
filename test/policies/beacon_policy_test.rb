require "test_helper"

class BeaconPolicyTest < PolicyAssertions::Test
  setup do
    setup_initial_user_fixtures
  end

  def test_index
    assert_not_permitted @member, Beacon
    assert_permit @admin, Beacon
    assert_permit @community_manager, Beacon
    assert_permit @general_manager, Beacon
  end

  def test_show
    assert_not_permitted @member, Beacon
    assert_permit @admin, Beacon
    assert_permit @community_manager, Beacon
    assert_permit @general_manager, Beacon
  end

  def test_new
    assert_not_permitted @member, Beacon
    assert_permit @admin, Beacon
    assert_not_permitted @community_manager, Beacon
    assert_permit @general_manager, Beacon
  end

  def test_create
    assert_not_permitted @member, Beacon
    assert_permit @admin, Beacon
    assert_not_permitted @community_manager, Beacon
    assert_permit @general_manager, Beacon
  end

  def test_update
    assert_not_permitted @member, Beacon
    assert_permit @admin, Beacon
    assert_not_permitted @community_manager, Beacon
    assert_permit @general_manager, Beacon
  end

  def test_edit
    assert_not_permitted @member, Beacon
    assert_permit @admin, Beacon
    assert_not_permitted @community_manager, Beacon
    assert_permit @general_manager, Beacon
  end

  def test_destroy
    assert_not_permitted @member, Beacon
    assert_permit @admin, Beacon
    assert_not_permitted @community_manager, Beacon
    assert_permit @general_manager, Beacon
  end
end
