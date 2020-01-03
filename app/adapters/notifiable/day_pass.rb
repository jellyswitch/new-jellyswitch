# typed: false
module Notifiable
  class DayPass < Notifiable::Default
    private

    def create_feed_item
      operator = day_pass_type.operator

      blob = {type: "day-pass", day_pass_id: id}
      FeedItemCreator.create_feed_item(operator, user, blob)
    end

    def send_notification
      operator = day_pass_type.operator
      message = "#{user.name} has purchased a day pass"

      unless user.approved?
        message = "Approval required: #{message}"
      end

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
