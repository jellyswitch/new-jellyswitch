require "test_helper"

class DayPassPolicyTest < PolicyAssertions::Test

  setup do
    setup_initial_user_fixtures
  end

  def test_index
    assert_permit @member, DayPass
    assert_permit @admin, DayPass
    assert_permit @general_manager, DayPass
    assert_permit @community_manager, DayPass
  end

  def test_new
    assert_permit @member, DayPass
    assert_permit @admin, DayPass
    assert_permit @general_manager, DayPass
    assert_permit @community_manager, DayPass
  end

  def test_create
    assert_permit @member, DayPass
    assert_permit @admin, DayPass
    assert_permit @community_manager, DayPass
    assert_permit @general_manager, DayPass
  end

  def test_show
    assert_permit @admin, organizations(:sierra_nevada_organization)
    assert_not_permitted @member, organizations(:sierra_nevada_organization)
    assert_permit @community_manager, organizations(:sierra_nevada_organization)
    assert_permit @general_manager, organizations(:sierra_nevada_organization)
  end

  def test_code
    assert_permit @member, DayPass
    assert_permit @admin, DayPass
    assert_permit @general_manager, DayPass
    assert_permit @community_manager, DayPass
  end

  def test_redeem_code
    assert_permit @member, DayPass
    assert_permit @admin, DayPass
    assert_permit @general_manager, DayPass
    assert_permit @community_manager, DayPass
  end
end