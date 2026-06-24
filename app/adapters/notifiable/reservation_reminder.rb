module Notifiable
  # Booker "come back — your door access is open" push (Phase 6, ADR 0013). Fired
  # by SendReservationReminderJob when access opens (building_access_window_minutes
  # before start), so the message and the door open together.
  class ReservationReminder < Notifiable::Default
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
      start = datetime_in.strftime("%-l:%M %p")
      "You can get into #{room.location.name} now — your #{room.name} booking starts at #{start}."
    end

    def recipients
      [self.user]
    end
  end
end
