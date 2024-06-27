class Billing::Reservations::SaveRoomReservation
  include Interactor
  include FeedItemCreator

  def call
    reservation = Reservation.new(context.reservation_params)

    should_charge = context.user.should_charge_for_reservation?(reservation.room.location, reservation.datetime_in.to_date) && reservation.room.hourly_rate_in_cents > 0

    reservation.paid = should_charge
    reservation.user = context.user

    context.reservation = reservation
    context.notifiable = reservation

    if !reservation.save
      context.fail!(message: "Unable to create reservation, please try again.")
    end
  end

  def rollback
    context.reservation.destroy
  end
end
