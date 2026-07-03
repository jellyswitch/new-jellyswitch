module Notifiable
  # Booker push at datetime_in — "your room is ready". Phase 6.
  class ReservationStarted < Notifiable::Default
    private

    def create_feed_item
    end

    def deep_link_data
      { screen: "MyReservations", type: "reservation", resource_id: id }
    end

    def should_send_notification?
      true
    end

    def message
      "Your #{room.name} booking has started."
    end

    def recipients
      [self.user]
    end
  end
end
