# typed: false
module Notifiable
  class Announcement < SimpleDelegator
    def notify
      # create_feed_item
      send_notification
    end

    private

    def create_feed_item
      operator = location.operator

      blob = {type: "checkin", checkin_id: id}
      FeedItemCreator.create_feed_item(operator, user, blob)
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
