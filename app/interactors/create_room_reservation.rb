class CreateRoomReservation
  include Interactor

  def call
    reservation = Reservation.new(context.reservation_params)

    reservation.user = context.user
    reservation.datetime_in = reservation.datetime_in.beginning_of_hour

    context.reservation = reservation
    if !reservation.save
      context.fail!(message: "Unable to save reservation.")
    end

    feed_item = FeedItem.new
    feed_item.operator = context.user.operator
    feed_item.user = context.user
    feed_item.blob = {type: "reservation", reservation_id: reservation.id}
    if !feed_item.save
      context.fail!(message: "Unable to generate feed item.")
    end
  end
end