class ReservableFactory
  def self.for(reservation)
    if reservation.user.out_of_band? || !reservation.user.card_added?
      Reservable::OutOfBand
    else
      Reservable::InBand
    end.new(reservation)
  end
end
