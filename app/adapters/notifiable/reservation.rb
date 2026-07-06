module Notifiable
  class Reservation < Notifiable::Default
    private

    def create_feed_item
      # Paid-room bookings already get a richer "paid-room-reservation" card from
      # Notifiable::PaidRoomReservation (via SendAdminNotificationForPaidRoom).
      # Emitting the generic card too rendered two cards per paid booking in the
      # admin feed, so skip it here — the paid-room card always fires for a paid
      # room (paid_room? ⇒ hourly_rate > 0 ⇒ charge_amount > 0).
      return if room.paid_room?
      blob = {type: "reservation", reservation_id: id}
      FeedItemCreator.create_feed_item(operator, location, user, blob)
    end

    def deep_link_data
      { type: "reservation", resource_id: id, path: "/reservations/#{id}" }
    end

    def should_send_notification?
      operator.reservation_notifications?
    end

    def message
      "#{user.name} has reserved #{room.name}"
    end

    def recipients
      operator.users.relevant_admins_of_location(location)
    end
  end
end
