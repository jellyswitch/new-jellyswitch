class Billing::Reservations::UpdateReservationDuration
  include Interactor

  def call
    reservation = context.reservation
    additional_duration = context.additional_duration

    reservation.minutes += additional_duration
    context.is_extend = true

    if !reservation.save
      context.fail!(message: "Failed to extend the reservation duration.")
    end
  end
end
