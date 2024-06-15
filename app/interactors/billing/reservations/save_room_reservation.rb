
class Billing::Reservations::SaveRoomReservation
  include Interactor
  include FeedItemCreator

  def call
    reservation = Reservation.new(context.reservation_params)

    reservation.user = context.user
    reservation.datetime_in = reservation.datetime_in

    context.reservation = reservation
    context.notifiable = reservation

    if !reservation.save
      context.fail!(message: "Unable to create reservation, please try again.")
    end
  end
end
