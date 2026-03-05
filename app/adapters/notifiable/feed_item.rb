module Notifiable
  class FeedItem < Notifiable::Default
    def create_feed_item
    end

    def deep_link_data
      { type: "feed_item", resource_id: id, path: "/feed_items/#{id}" }
    end

    def should_send_notification?
      operator.post_notifications?
    end

    def message
      "#{user.name} has posted a new management note"
    end

    def recipients
      operator.users.relevant_admins_of_location(location)
    end
  end
end
