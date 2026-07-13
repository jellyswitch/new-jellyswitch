
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
        next false if user.email_opted_out?
        next true if user.admin_of_location?(location) || user.superadmin?
        next false unless user.member_at_location?(location)

        active_patron = user.subscriptions.active.any? ||
          user.day_passes.where(day: Date.current).any? ||
          user.organization&.office_leases&.active&.any?

        # Suppression stops MARKETING — not operational announcements to
        # someone currently in the building. A committed member who said
        # "I'm moving" months before their end date still needs house news
        # while they're here; only non-patrons stay filtered.
        next false if user.marketing_suppressed? && !active_patron

        active_patron
      end
    end
  end
end
