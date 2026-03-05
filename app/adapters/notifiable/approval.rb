module Notifiable
  class Approval < Notifiable::Default
    private

    def create_feed_item
      # No feed item for approvals
    end

    def deep_link_data
      { type: "approval", resource_id: id, path: "/home" }
    end

    def should_send_notification?
      true
    end

    def message
      "You've been approved! Welcome to #{operator.name}."
    end

    def recipients
      [self]
    end
  end
end
