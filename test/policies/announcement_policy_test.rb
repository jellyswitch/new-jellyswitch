require "test_helper"

class AnnouncementPolicyTest < PolicyAssertions::Test

  setup do
    setup_initial_user_fixtures
    @operator = operators(:cowork_tahoe)
  end

  def test_index
    assert_not_permitted @member, Announcements
    assert_permit @admin, Announcements
    assert_permit @community_manager, Announcements
    assert_permit @general_manager, Announcements
  end
end
