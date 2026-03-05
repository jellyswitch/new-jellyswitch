
module Notifiable
  class WeeklyUpdate < Notifiable::Default
    private

    def create_feed_item
      blob = {type: "weekly-update", weekly_update_id: id}
      user = ::User.first # Dave???
      FeedItemCreator.create_feed_item(operator, location, user, blob, created_at: created_at)
    end

    def deep_link_data
      { type: "weekly_update", resource_id: id, path: "/weekly_updates/#{id}" }
    end

    def should_send_notification?
      true
    end

    def message
      "Your weekly update has been posted in the feed. Take a look!"
    end

    def recipients
      operator.users.relevant_admins_of_location(location)
    end
  end
end
