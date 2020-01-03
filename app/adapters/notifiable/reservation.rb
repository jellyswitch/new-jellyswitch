module Notifiable
  class Reservation < SimpleDelegator
    def notify
      create_feed_item
      send_notification
    end

    private

    def create_feed_item
      blob = {type: "reservation", reservation_id: id}
      FeedItemCreator.create_feed_item(room.operator, user, blob)
    end

    def send_notification
      message = "#{user.name} posted an announcement to #{room.operator.name}."
      message = "#{user.name} has reserved #{room.name}"

      result = Notifications::PushNotifier.call(
        message: message,
        operator: room.operator
      )

      if result.failure?
        Rollbar.error("Error pushing notification: #{result.message}")
      end
    end
  end
end
