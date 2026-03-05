
module Notifiable
  class Subscription < Notifiable::Default
    private

    def create_feed_item
      blob = { type: 'subscription', subscription_id: id }

      FeedItemCreator.create_feed_item(operator, location, subscribable, blob, created_at: created_at)
    end

    def deep_link_data
      { type: "subscription", resource_id: id, path: "/subscriptions/#{id}" }
    end

    def should_send_notification?
      operator.membership_notifications?
    end

    def message
      message = "#{subscribable.name} has subscribed to #{plan.pretty_name}"

      unless subscribable.approved?
        message = "Approval required: #{message}"
      end
      message
    end

    def recipients
      operator.users.relevant_admins_of_location(location)
    end
  end
end
