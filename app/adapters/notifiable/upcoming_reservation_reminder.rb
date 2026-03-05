module Notifiable
  class UpcomingReservationReminder < Notifiable::Default
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
      "Another party has reserved #{room.name}, please prepare to wrap up your meeting."
    end

    def recipients
      [self.user]
    end
  end
end
