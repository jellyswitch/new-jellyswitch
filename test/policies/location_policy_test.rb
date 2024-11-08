require "test_helper"

class LocationPolicyTest < PolicyAssertions::Test

  setup do
    setup_initial_user_fixtures
  end

  def test_index
    assert_not_permitted @member, Location
    assert_permit @admin, Location
    assert_permit @community_manager, Location
    assert_permit @general_manager, Location
  end

  def test_new
    assert_not_permitted @member, Location
    assert_permit @admin, Location
    assert_not_permitted @community_manager, Location
    assert_not_permitted @general_manager, Location
  end

  def test_show
    assert_not_permitted @member, Location
    assert_permit @admin, Location
    assert_not_permitted @community_manager, Location
    assert_permit @general_manager, Location
  end

  def test_create
    assert_not_permitted @member, Location
    assert_permit @admin, Location
    assert_not_permitted @community_manager, Location
    assert_not_permitted @general_manager, Location
  end

  def test_edit
    assert_not_permitted @member, Location
    assert_permit @admin, locations(:cowork_tahoe_location)
    assert_not_permitted @admin, create(:location)
    assert_not_permitted @community_manager, Location
    assert_permit @general_manager, locations(:cowork_tahoe_location)
    assert_not_permitted @general_manager, create(:location)
  end

  def test_update
    assert_not_permitted @member, Location
    assert_permit @admin, Location
    assert_not_permitted @community_manager, Location
    assert_permit @general_manager, Location
  end

  def test_allow_hourly
    assert_not_permitted @member, Location
    assert_permit @admin, Location
    assert_not_permitted @community_manager, Location
    assert_not_permitted @general_manager, Location
  end

  def test_new_users_get_free_day_pass
    assert_not_permitted @member, Location
    assert_permit @admin, Location
    assert_not_permitted @community_manager, Location
    assert_not_permitted @general_manager, Location
  end

  def test_visible
    assert_not_permitted @member, Location
    assert_permit @admin, Location
    assert_not_permitted @community_manager, Location
    assert_not_permitted @general_manager, Location
  end
end