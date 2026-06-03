require "test_helper"

class MemberFeedbackTest < ActiveSupport::TestCase
  def setup
    @location = locations(:cowork_tahoe_location)
    @member   = users(:cowork_tahoe_member)
    @host     = users(:cowork_tahoe_admin) # staff — different user than the member
    @operator = @member.operator
  end

  def thread(comment: nil)
    MemberFeedback.create!(operator: @operator, location: @location, user: @member, comment: comment)
  end

  test "with_member_message excludes host-greeting-only threads" do
    greeting_only = thread
    FeedbackReply.create!(member_feedback: greeting_only, user: @host, operator: @operator, body: "Hi! Any questions?")

    assert_not_includes MemberFeedback.where(operator: @operator).with_member_message, greeting_only
  end

  test "with_member_message includes a thread once the member replies" do
    t = thread
    FeedbackReply.create!(member_feedback: t, user: @host, operator: @operator, body: "Hi!")        # host greeting
    FeedbackReply.create!(member_feedback: t, user: @member, operator: @operator, body: "A question") # member reply

    assert_includes MemberFeedback.where(operator: @operator).with_member_message, t
  end

  test "with_member_message includes a member-initiated thread (non-blank comment)" do
    t = thread(comment: "I need help")
    assert_includes MemberFeedback.where(operator: @operator).with_member_message, t
  end

  test "not_dismissed excludes dismissed threads" do
    t = thread(comment: "hi")
    assert_includes MemberFeedback.where(operator: @operator).not_dismissed, t

    t.update!(dismissed_at: Time.current)
    assert_not_includes MemberFeedback.where(operator: @operator).not_dismissed, t
  end
end
