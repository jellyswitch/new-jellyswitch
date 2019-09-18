# typed: true
class Billing::Reservations::SaveRoomReservation
  include Interactor
  include FeedItemCreator

  def call
    reservation = Reservation.new(context.reservation_params)

    reservation.user = context.user
    reservation.datetime_in = reservation.datetime_in.beginning_of_half_hour

    context.reservation = reservation
    if !reservation.save
      context.fail!(message: "Unable to save reservation.")
    end

    blob = {type: "reservation", reservation_id: reservation.id}
    create_feed_item(context.user.operator, context.user, blob)

    message = "#{reservation.user.name} has reserved #{reservation.room.name}"
  end
end