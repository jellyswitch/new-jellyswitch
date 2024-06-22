class CancelReservation
  include Interactor

  def call
    reservation = context.reservation
    current_user = context.current_user

    reservation.cancelled = true

    if !reservation.save
      context.fail!(message: "Unable to cancel reservation.")
    end
  end
end
