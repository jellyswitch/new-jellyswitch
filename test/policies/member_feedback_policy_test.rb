require "test_helper"

class MemberFeedbackPolicyTest < PolicyAssertions::Test

  setup do
    setup_initial_user_fixtures
  end

  def test_index
    assert_not_permitted @member, MemberFeedback
    assert_permit @admin, MemberFeedback
    assert_permit @community_manager, MemberFeedback
    assert_permit @general_manager, MemberFeedback
  end

  def test_show
    assert_not_permitted @member, MemberFeedback
    assert_permit @admin, MemberFeedback
    assert_permit @community_manager, MemberFeedback
    assert_permit @general_manager, MemberFeedback
  end
end