
module Notifiable
  class Announcement < Notifiable::Default
    private

    def create_feed_item
      blob = {type: "announcement", announcement_id: id}
      FeedItemCreator.create_feed_item(operator, location, user, blob, created_at: created_at)
    end

    def should_send_notification?
      true
    end

    def message
      "New announcement from #{operator.name}: #{body}"
    end

    def recipients
      operator.users.all.select do |user|
        user.admin_of_location?(location) || (user.superadmin? && user.currently_at_location?(location)) || user.member_at_location?(location)
      end
    end
  end
end
