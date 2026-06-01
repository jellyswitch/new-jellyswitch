require 'test_helper'

class FeedbackReplyTest < ActiveSupport::TestCase
  def setup
    @location = locations(:cowork_tahoe_location)
    @member = users(:cowork_tahoe_member)
    @operator = @member.operator
    @feedback = MemberFeedback.create!(
      operator: @operator, location: @location, user: @member, comment: nil,
      created_at: 10.days.ago, updated_at: 10.days.ago,
    )
  end

  test "creating a reply touches the parent thread's updated_at" do
    assert_changes -> { @feedback.reload.updated_at } do
      FeedbackReply.create!(
        member_feedback: @feedback, user: @member, operator: @operator, body: "hi",
      )
    end
    assert_in_delta Time.current, @feedback.reload.updated_at, 5.seconds
  end

  test "threads sort by last activity, not thread creation" do
    # Older thread, but it gets a fresh reply → should sort first.
    other = MemberFeedback.create!(
      operator: @operator, location: @location, user: @member, comment: nil,
      created_at: 1.day.ago, updated_at: 1.day.ago,
    )

    # @feedback was created 10 days ago; bump it with a reply now.
    FeedbackReply.create!(
      member_feedback: @feedback, user: @member, operator: @operator, body: "still here?",
    )

    ordered_ids = MemberFeedback.where(operator: @operator).order(updated_at: :desc).pluck(:id)
    assert_equal @feedback.id, ordered_ids.first,
      "thread with the most recent reply should sort first"
    assert ordered_ids.index(@feedback.id) < ordered_ids.index(other.id),
      "freshly-replied thread should outrank the newer-but-quiet thread"
  end
end
