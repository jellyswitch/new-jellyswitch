module Notifiable
  class FeedItemComment < Notifiable::Default
    def create_feed_item
    end

    def should_send_notification?
      operator.post_notifications?
    end

    def message
      if feed_item.type === "announcement"
        "#{user.name} replied to an announcement post"
      else
        "#{user.name} replied to a recent management note"
      end
    end

    def recipients
      operator.users.admins
    end
  end
end
