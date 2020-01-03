# typed: false
module Notifiable
  class Announcement < Notifiable::Default
    private

    def create_feed_item
      blob = {type: "announcement", announcement_id: id}
      FeedItemCreator.create_feed_item(operator, user, blob, created_at: created_at)
    end

    def should_send_notification?
      true
    end

    def send_notification
      message = "#{user.name} posted an announcement to #{operator.name}."

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
