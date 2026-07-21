class SendAdminNotificationForPaidRoom
  include Interactor

  delegate :reservation, to: :context

  def call
    return if context.comp # comped by staff — no revenue to announce

    if reservation.room.paid_room?
      SendNotificationsJob.perform_later(reservation, 'PaidRoomReservation')
    end
  end
end
