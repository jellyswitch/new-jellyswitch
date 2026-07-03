class ReservationValidator < ActiveModel::Validator
  def validate(record)
    return if record.cancelled?

    overlapping_reservations = find_overlapping_reservations(record)

    if overlapping_reservations.exists?
      # Precise + tagged: the message reaches members verbatim (old app
      # bundles render data.error raw), and the :overlap tag lets the API
      # detect a conflict and return 409 with a structured payload.
      record.errors.add(:base, :overlap,
        message: "#{record.room&.name || 'This room'} is no longer free #{record.window_label}.")
    end
  end

  private

  def find_overlapping_reservations(record)
    Reservation.overlapping(record.datetime_in, record.datetime_out)
               .where(room_id: record.room_id)
               .where.not(id: record.id)
  end
end
