class BackfillFeedbackRepliesFromFeedComments < ActiveRecord::Migration[7.0]
  def up
    cutoff = 2.days.ago

    # Find all feedback-type FeedItems with comments in the last 2 days
    FeedItem.where("blob->>'type' = ?", "feedback").find_each do |feed_item|
      begin
        member_feedback = feed_item.member_feedback
      rescue ActiveRecord::RecordNotFound
        next
      end
      next unless member_feedback

      operator = feed_item.operator
      ActsAsTenant.with_tenant(operator) do
        feed_item.feed_item_comments.where("created_at >= ?", cutoff).find_each do |comment|
          # Skip if a FeedbackReply already exists with the same body from the same user
          existing = member_feedback.feedback_replies.find_by(
            user: comment.user,
            body: comment.comment
          )
          next if existing

          reply = FeedbackReply.create!(
            member_feedback: member_feedback,
            user: comment.user,
            operator: operator,
            body: comment.comment,
            created_at: comment.created_at,
            updated_at: comment.updated_at
          )

          # Send push notification to the member
          begin
            NotifiableFactory.for(reply).notify
            puts "Notified #{member_feedback.user.name} about reply from #{comment.user.name}"
          rescue => e
            puts "Notification error for feedback #{member_feedback.id}: #{e.message}"
          end
        end
      end
    end
  end

  def down
    # No-op — can't undo notifications
  end
end
