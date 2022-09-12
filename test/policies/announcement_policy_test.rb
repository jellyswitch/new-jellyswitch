require "test_helper"

class AnnouncementPolicyTest < PolicyAssertions::Test

  setup do
    @admin = users(:cowork_tahoe_admin)
    @member = users(:cowork_tahoe_member)
    @community_manager = users(:cowork_tahoe_community_manager)
    @general_manager = users(:cowork_tahoe_general_manager)
    @operator = operators(:cowork_tahoe)
  end

  def test_index
    assert_not_permitted @member, Announcements
    assert_permit @admin, Announcements
    assert_permit @community_manager, Announcements
    assert_permit @general_manager, Announcements
  end
end
