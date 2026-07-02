module Notifiable
  # Member-facing push on a successful reservation capture (Phase 6) — the push
  # counterpart of the receipt email (UserMailer.meeting_room_charged). Reads the
  # actual captured amount; dispatched from ChargeAtBooking on the capture path.
  class ReservationCharged < Notifiable::Default
    private

    def create_feed_item
    end

    def deep_link_data
      { screen: "MyReservations", type: "reservation", resource_id: id }
    end

    def should_send_notification?
      captured_amount_in_cents.to_i > 0
    end

    def message
      amount = format("$%.2f", captured_amount_in_cents.to_i / 100.0)
      "You were charged #{amount} for #{room.name} on #{datetime_in.strftime('%b %-d')}."
    end

    def recipients
      [self.user]
    end
  end
end
