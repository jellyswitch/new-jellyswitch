module Notifiable
  class Post < Notifiable::Default
    private

    def create_feed_item
      blob = {type: "post", post_id: id}
      FeedItemCreator.create_feed_item(operator, user, blob, created_at: created_at)
    end

    def should_send_notification?
      true
    end

    def send_notification
      message = "New bulletin board post from #{user.name}: #{title}"

      result = Notifications::PushNotifier.call(
        message: message,
        operator: operator,
        members: false # TODO
      )

      if result.failure?
        Rollbar.error("Error pushing notification: #{result.message}")
      end
    end
  end
end
