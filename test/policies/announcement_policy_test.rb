require "test_helper"

class AnnouncementPolicyTest < PolicyAssertions::Test

  setup do
    setup_initial_user_fixtures
    @operator = operators(:cowork_tahoe)
  end

  def test_index
    assert_not_permitted @member, Announcement
    assert_permit @admin, Announcement
    assert_permit @community_manager, Announcement
    assert_permit @general_manager, Announcement
  end
end
