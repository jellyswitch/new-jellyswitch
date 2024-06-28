class ReservationValidator < ActiveModel::Validator
  def validate(record)
    return if record.cancelled?

    overlapping_reservations = find_overlapping_reservations(record)

    if overlapping_reservations.exists?
      record.errors.add(:base, "The requested time slot conflicts with an existing reservation. Please choose a different time or room.")
    end
  end

  private

  def find_overlapping_reservations(record)
    Reservation.overlapping(record.datetime_in, record.datetime_out)
               .where(room_id: record.room_id)
               .where.not(id: record.id)
  end
end
