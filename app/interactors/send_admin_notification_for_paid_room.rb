class SendAdminNotificationForPaidRoom
  include Interactor

  delegate :reservation, to: :context

  def call
    if reservation.room.paid_room?
      SendNotificationsJob.perform_later(reservation, 'PaidRoomReservation')
    end
  end
end
