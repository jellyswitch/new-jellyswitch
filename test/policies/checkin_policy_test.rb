require "test_helper"

class CheckinPolicyTest < PolicyAssertions::Test
  include PolicyHelpers

  setup do
    setup_initial_user_fixtures
  end

  def test_new
    assert_permit @member, Checkin
    assert_permit @admin, Checkin
    assert_permit @community_manager, Checkin
    assert_permit @general_manager, Checkin
  end

  def test_required
    assert_permit @member, Checkin
    assert_permit @admin, Checkin
    assert_permit @community_manager, Checkin
    assert_permit @general_manager, Checkin
  end

  def test_create
    assert_permit @member, Checkin
    assert_permit @admin, Checkin
    assert_permit @community_manager, Checkin
    assert_permit @general_manager, Checkin
  end

  def test_show
    assert_not_permitted @member, Checkin
    assert_permit @admin, Checkin
    assert_permit @community_manager, Checkin
    assert_permit @general_manager, Checkin
  end

  def test_index
    assert_not_permitted @member, Checkin
    assert_permit @admin, Checkin
    assert_permit @community_manager, Checkin
    assert_permit @general_manager, Checkin
  end

  # def test_destroy
  #   assert_not_permitted @member, Checkin
  #   assert_permit @admin, Checkin
  #   assert_permit @community_manager, Checkin
  #   assert_permit @general_manager, Checkin
  # end
end
