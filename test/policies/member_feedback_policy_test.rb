require "test_helper"

class MemberFeedbackPolicyTest < PolicyAssertions::Test

  setup do
    setup_initial_user_fixtures
    # Use a feedback instance with a different user so @member is not the record owner
    @feedback = create(:member_feedback)
  end

  def test_index
    assert_not_permitted @member, MemberFeedback
    assert_permit @admin, MemberFeedback
    assert_permit @community_manager, MemberFeedback
    assert_permit @general_manager, MemberFeedback
  end

  def test_show
    assert_not_permitted @member, @feedback
    assert_permit @admin, @feedback
    assert_permit @community_manager, @feedback
    assert_permit @general_manager, @feedback
  end
end
