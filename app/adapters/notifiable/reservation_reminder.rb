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
      wait = "Your #{room.name} booking starts at #{start}. Please wait until then to use the room, since it may be in use."
      # Only a paid booking is what opens the door for this person. Day passers,
      # members and admins already have access (they book with paid = false), so
      # telling them they "have access now" reads as ROOM access (9/25).
      return wait unless paid?

      "You now have access to #{room.location.name}. #{wait}"
    end

    def recipients
      [self.user]
    end
  end
end
