require "test_helper"

class CheckinPolicyTest < PolicyAssertions::Test
  include PolicyHelpers

  setup do
    @admin = users(:cowork_tahoe_admin)
    @member = users(:cowork_tahoe_member)
    @community_manager = users(:cowork_tahoe_community_manager)
    @general_manager = users(:cowork_tahoe_general_manager)
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
