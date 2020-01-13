# typed: false
module Notifiable
  class Subscription < Notifiable::Default
    private

    def create_feed_item
      operator = subscribable.operator
      blob = { type: 'subscription', subscription_id: id }

      FeedItemCreator.create_feed_item(operator, subscribable, blob, created_at: created_at)
    end

    def should_send_notification?
      subscribable.operator.membership_notifications?
    end

    def send_notification
      operator = subscribable.operator
      message = "#{subscribable.name} has subscribed to #{plan.pretty_name}"

      unless subscribable.approved?
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
