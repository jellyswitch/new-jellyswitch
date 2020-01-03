module Notifiable
  class User < Notifiable::Default
    private

    def create_feed_item
      blob = { type: "new-user" }
      FeedItemCreator.create_feed_item(operator, self.__getobj__, blob)
    end

    def should_send_notification?
      operator.signup_notifications?
    end

    def send_notification
      message = "New user signup"

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
