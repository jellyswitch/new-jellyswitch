class CancelReservation
  include Interactor

  def call
    reservation = context.reservation
    current_user = context.current_user

    if reservation.room.paid_room? && !current_user.admin_or_manager?
      context.fail!(message: "You are not allowed to cancel this reservation since this is a paid room, please contact the workspace admin for assistance.")
    end

    reservation.cancelled = true

    if !reservation.save
      context.fail!(message: "Unable to cancel reservation.")
    end
  end
end
