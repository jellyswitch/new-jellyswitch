
module Reservable
  class DefaultReservation < SimpleDelegator
    attr_accessor :reservation

    def initialize(reservation)
      @reservation = reservation
    end

    def invoice_args
      {
        customer: reservation.user.stripe_customer_id_for_location(reservation.room.location),
        auto_advance: true
      }
    end
  end
end