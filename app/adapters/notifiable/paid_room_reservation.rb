module Notifiable
  class PaidRoomReservation < Notifiable::Default
    private

    def create_feed_item
    end

    def should_send_notification?
      room.paid_room?
    end

    def message
      "#{user.name} has booked a paid meeting room"
    end

    def recipients
      operator.users.relevant_admins_of_location(location)
    end
  end
end
