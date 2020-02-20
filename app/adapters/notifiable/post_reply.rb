module Notifiable
  class PostReply < Notifiable::Default
    private

    def create_feed_item
      blob = {type: "post-reply", post_reply_id: id}
      FeedItemCreator.create_feed_item(operator, user, blob, created_at: created_at)
    end

    def should_send_notification?
      true
    end

    def send_notification
      message = "#{user.name} has replied to your post"
      recipients = [post.user]

      result = Notifications::PushNotifier.call(
        message: message,
        operator: operator,
        members: false,
        recipients: recipients
      )

      if result.failure?
        Rollbar.error("Error pushing notification: #{result.message}")
      end
    end
  end
end
