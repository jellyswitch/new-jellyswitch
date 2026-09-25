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
      # Building access only — the room itself may still be booked by someone
      # else until start. "Get into ... now" was read as room access (9/25).
      "The building is open to you now. Your #{room.name} booking starts at #{start} — " \
        "please wait until then to use the room, as it may be in use."
    end

    def recipients
      [self.user]
    end
  end
end
