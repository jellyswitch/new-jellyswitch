# typed: false
module Notifiable
  class Checkin < SimpleDelegator
    def notify
      create_feed_item
      send_notification
    end

    private

    def create_feed_item
      operator = location.operator

      blob = {type: "checkin", checkin_id: id}
      FeedItemCreator.create_feed_item(operator, user, blob)
    end

    def send_notification
      operator = location.operator
      message = "#{user.name} has checked into #{location.name}."

      unless user.approved?
        message = "Approval required: #{message}"

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
end
