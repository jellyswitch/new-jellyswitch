
module Notifiable
  class Announcement < Notifiable::Default
    private

    def create_feed_item
    end

    def deep_link_data
      { type: "announcement", resource_id: id, path: "/announcements/#{id}" }
    end

    def should_send_notification?
      true
    end

    def message
      "New announcement from #{operator.name}: #{body}"
    end

    def recipients
      operator.users.visible.select do |user|
        next false if user.email_opted_out? || user.marketing_suppressed?
        next true if user.admin_of_location?(location) || user.superadmin?
        next false unless user.member_at_location?(location)

        user.subscriptions.active.any? ||
          user.day_passes.where(day: Date.current).any? ||
          user.organization&.office_leases&.active&.any?
      end
    end
  end
end
