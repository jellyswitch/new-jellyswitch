module Notifiable
  class PaidRoomReservation < Notifiable::Default
    private

    def create_feed_item
      blob = {type: "paid-room-reservation", reservation_id: id, charge_amount_in_cents: charge_amount}
      FeedItemCreator.create_feed_item(operator, location, user, blob)
    end

    def deep_link_data
      { type: "reservation", resource_id: id, path: "/reservations/#{id}" }
    end

    def should_send_notification?
      room.paid_room?
    end

    def message
      amount = charge_amount.to_f / 100.0
      "#{user.name} has booked #{room.name} for #{'$%.2f' % amount}"
    end

    def recipients
      operator.users.relevant_admins_of_location(location)
    end
  end
end
