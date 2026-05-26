require "test_helper"

# Behavior for `MemberFeedback#can_rate?`. The mobile app surfaces the
# "rate this experience" CTA only when this returns true, so the rules
# here directly drive the UI.
#
# Product intent (David, 2026-05-25): the rating should appear only after
# the conversation has "wrapped up" — operationalized as 24h of silence
# since the last reply on either side. Showing the rating immediately
# after the first staff reply (the previous behavior) felt premature.
class MemberFeedbackCanRateTest < ActiveSupport::TestCase
  setup do
    @operator = operators(:cowork_tahoe)
    @member   = users(:cowork_tahoe_member)
    @admin    = users(:cowork_tahoe_admin)
    @feedback = MemberFeedback.create!(
      operator: @operator,
      user:     @member,
      comment:  "Q: where's the coffee?",
    )
  end

  test "false when there are no replies at all" do
    refute @feedback.can_rate?
  end

  test "false when only the member has replied" do
    FeedbackReply.create!(member_feedback: @feedback, operator: @operator, user: @member, body: "bumping this")
    refute @feedback.can_rate?
  end

  test "false when the admin replied <24h ago (conversation still active)" do
    travel_to 30.minutes.ago do
      FeedbackReply.create!(member_feedback: @feedback, operator: @operator, user: @admin, body: "On the third floor!")
    end
    refute @feedback.can_rate?, "rating CTA should wait for 24h of silence before appearing"
  end

  test "true when the admin replied >24h ago and nothing has happened since" do
    travel_to 25.hours.ago do
      FeedbackReply.create!(member_feedback: @feedback, operator: @operator, user: @admin, body: "On the third floor!")
    end
    assert @feedback.can_rate?
  end

  test "false when the member sent a follow-up after the admin reply, even if the admin reply was >24h ago" do
    travel_to 30.hours.ago do
      FeedbackReply.create!(member_feedback: @feedback, operator: @operator, user: @admin, body: "On the third floor!")
    end
    travel_to 10.minutes.ago do
      FeedbackReply.create!(member_feedback: @feedback, operator: @operator, user: @member, body: "Thanks! One more thing...")
    end
    refute @feedback.can_rate?, "follow-up reply resets the silence window"
  end

  test "false when already rated" do
    travel_to 25.hours.ago do
      FeedbackReply.create!(member_feedback: @feedback, operator: @operator, user: @admin, body: "On the third floor!")
    end
    @feedback.update!(rating: 5)
    refute @feedback.can_rate?, "rating UI should not re-appear once a rating exists"
  end
end
