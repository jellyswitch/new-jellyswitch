require "test_helper"

class OfficePolicyTest < PolicyAssertions::Test
  setup do
    setup_initial_user_fixtures
  end

  def test_index
    assert_not_permitted @member, Office
    assert_permit @admin, Office
    assert_permit @community_manager, Office
    assert_permit @general_manager, Office
    assert_permit @superadmin, Office
  end

  def test_show
    assert_not_permitted @member, Office
    assert_permit @admin, Office
    assert_permit @community_manager, Office
    assert_permit @general_manager, Office
    assert_permit @superadmin, Office
  end

  def test_new
    assert_not_permitted @member, Office
    assert_permit @admin, Office
    assert_permit @community_manager, Office
    assert_permit @general_manager, Office
    assert_permit @superadmin, Office
  end

  def test_create
    assert_not_permitted @member, Office
    assert_permit @admin, Office
    assert_permit @community_manager, Office
    assert_permit @general_manager, Office
    assert_permit @superadmin, Office
  end

  def test_edit
    assert_not_permitted @member, Office
    assert_permit @admin, Office
    assert_permit @community_manager, Office
    assert_permit @general_manager, Office
    assert_permit @superadmin, Office
  end

  def test_update
    assert_not_permitted @member, Office
    assert_permit @admin, Office
    assert_permit @community_manager, Office
    assert_permit @general_manager, Office
    assert_permit @superadmin, Office
  end

  def test_available
    assert_not_permitted @member, Office
    assert_permit @admin, Office
    assert_permit @community_manager, Office
    assert_permit @general_manager, Office
    assert_permit @superadmin, Office
  end

  def test_upcoming_renewals
    assert_not_permitted @member, Office
    assert_permit @admin, Office
    assert_permit @community_manager, Office
    assert_permit @general_manager, Office
    assert_permit @superadmin, Office
  end

  def test_upcoming_renewals
    assert_not_permitted @member, Office
    assert_permit @admin, Office
    assert_permit @community_manager, Office
    assert_permit @general_manager, Office
    assert_permit @superadmin, Office
  end

  def test_destroy
    office_with_active_lease = offices(:office_23b)

    assert_not_permitted @member, office_with_active_lease
    assert_not_permitted @superadmin, office_with_active_lease

    office_no_active_lease = offices(:free_office)

    assert_not_permitted @member, office_no_active_lease
    assert_not_permitted @community_manager, office_no_active_lease
    assert_not_permitted @general_manager, office_no_active_lease
    assert_permit @superadmin, office_no_active_lease
  end
end
