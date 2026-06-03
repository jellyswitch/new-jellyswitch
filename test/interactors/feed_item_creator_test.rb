require "test_helper"

class FeedItemCreatorTest < ActiveSupport::TestCase
  def setup
    @location = locations(:cowork_tahoe_location)
    @member   = users(:cowork_tahoe_member)
    @operator = @member.operator
    @thread   = MemberFeedback.create!(operator: @operator, location: @location, user: @member, comment: nil)
  end

  def feedback_blob(thread, body)
    { type: "feedback", member_feedback_id: thread.id, body: body }
  end

  test "upsert collapses a conversation into one feed item showing the latest message" do
    assert_difference -> { FeedItem.unscoped.for_operator(@operator).count }, 1 do
      FeedItemCreator.upsert_feedback_feed_item(@operator, @location, @member, feedback_blob(@thread, "first"))
      FeedItemCreator.upsert_feedback_feed_item(@operator, @location, @member, feedback_blob(@thread, "second"))
    end

    item = FeedItem.unscoped.for_operator(@operator)
                   .where("blob->>'member_feedback_id' = ?", @thread.id.to_s).sole
    assert_equal "second", item.blob["body"]
  end

  test "different conversations get their own feed items" do
    other = MemberFeedback.create!(operator: @operator, location: @location, user: @member, comment: nil)
    assert_difference -> { FeedItem.unscoped.for_operator(@operator).count }, 2 do
      FeedItemCreator.upsert_feedback_feed_item(@operator, @location, @member, feedback_blob(@thread, "a"))
      FeedItemCreator.upsert_feedback_feed_item(@operator, @location, @member, feedback_blob(other, "b"))
    end
  end
end
