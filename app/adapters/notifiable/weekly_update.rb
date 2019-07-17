# typed: false
module Notifiable
  class WeeklyUpdate < SimpleDelegator
    def notify
      create_feed_item
      send_notification
    end

    private

    def create_feed_item
      blob = {type: "weekly-update", weekly_update_id: id}
      user = User.first # Dave???
      FeedItemCreator.create_feed_item(operator, user, blob)
    end

    def send_notification
      message = "Your weekly update has been posted in the feed. Take a look!"

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
