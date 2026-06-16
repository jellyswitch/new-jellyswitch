module Notifiable
  class DayPassBundle < Notifiable::Default
    def create_feed_item
      blob = {
        type: "day-pass-bundle",
        day_pass_bundle_id: id,
        user_name: user.name,
        message: "#{user.name} purchased a #{quantity_purchased}-Pack"
      }
      FeedItemCreator.create_feed_item(operator, location, user, blob)
    end

    def deep_link_data
      { type: "day_pass_bundle", resource_id: id, path: "/day_pass_bundles/#{id}" }
    end

    def should_send_notification?
      operator.day_pass_notifications?
    end

    def message
      "#{user.name} purchased a #{quantity_purchased}-Pack"
    end

    def recipients
      operator.users.relevant_admins_of_location(location)
    end
  end
end
