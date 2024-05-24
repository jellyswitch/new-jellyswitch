module Notifiable
  class PaidRoomReservation < Notifiable::Default
    private

    def create_feed_item
      blob = {type: "reservation", reservation_id: id}
      FeedItemCreator.create_feed_item(operator, user, blob)
    end

    def should_send_notification?
      room.paid_room?
    end

    def message
      "#{user.name} has booked a paid meeting room"
    end

    def recipients
      operator.users.admins
    end
  end
end
