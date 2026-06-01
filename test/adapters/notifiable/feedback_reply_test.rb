require 'test_helper'

class Notifiable::FeedbackReplyTest < ActiveSupport::TestCase
  def setup
    @location = locations(:cowork_tahoe_location)
    @member = users(:cowork_tahoe_member)
    @admin = users(:cowork_tahoe_admin)
    @operator = @member.operator

    # Greeting-first thread: host messages first, member's comment is blank.
    # This is the shape MemberFeedback::EnsureHostGreeting produces, and the
    # reason member messages now arrive as replies rather than new feedback.
    @feedback = MemberFeedback.create!(
      operator: @operator,
      location: @location,
      user: @member,
      comment: nil,
    )
  end

  test "member reply creates a feedback feed item so it surfaces as an action item" do
    reply = FeedbackReply.create!(
      member_feedback: @feedback,
      user: @member,
      operator: @operator,
      body: "Could you buzz me in? I'm here to grab a jacket.",
    )

    assert_difference -> { FeedItem.where("blob->>'type' = ?", "feedback").count }, 1 do
      Notifiable::FeedbackReply.new(reply).send(:create_feed_item)
    end

    fi = FeedItem.where("blob->>'type' = ?", "feedback").order(:created_at).last
    assert_equal @feedback.id, fi.blob["member_feedback_id"].to_i
    assert_equal reply.id, fi.blob["feedback_reply_id"].to_i
    assert_equal reply.body, fi.blob["body"]
    assert_equal @member.id, fi.user_id
    assert_equal @location.id, fi.location_id
  end

  test "admin reply does NOT create a feed item (stays private to the member)" do
    reply = FeedbackReply.create!(
      member_feedback: @feedback,
      user: @admin,
      operator: @operator,
      body: "Buzzing you in now!",
    )

    assert_no_difference -> { FeedItem.count } do
      Notifiable::FeedbackReply.new(reply).send(:create_feed_item)
    end
  end
end
