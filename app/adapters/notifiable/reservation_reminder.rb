module Notifiable
  class ReservationReminder < Notifiable::Default
    private

    def create_feed_item
    end

    def deep_link_data
      { type: "reservation", resource_id: id, path: "/reservations/#{id}" }
    end

    def should_send_notification?
      true
    end

    def message
      "Reminder: Your reservation in #{room.name} starts in 15 minutes."
    end

    def recipients
      [self.user]
    end
  end
end
