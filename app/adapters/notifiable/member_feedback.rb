module Notifiable
  class MemberFeedback < Notifiable::Default
    private

    def create_feed_item
      blob = {type: "feedback", member_feedback_id: id}
      FeedItemCreator.create_feed_item(operator, user, blob, created_at: created_at)
    end

    def should_send_notification?
      operator.member_feedback_notifications?
    end

    def send_notification
      message = "New member feedback"

      result = Notifications::PushNotifier.call(
        message: message,
        operator: operator
      )

      if result.failure?
        Rollbar.error("Error pushing notification: #{result.message}")
      end
    end
  end
end
