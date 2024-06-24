class ReservationValidator < ActiveModel::Validator
  def validate(record)
    return true if record.cancelled?

    start_time = record.datetime_in
    end_time = record.datetime_in + record.minutes.minutes

    unavailable_rooms = Room.unavailable(date: record.datetime_in.to_date, time: start_time.strftime("%H:%M"), duration: record.minutes)

    if record.persisted?
      return true # TODO: Implement this
    end

    if unavailable_rooms.exists?(id: record.room_id)
      record.errors.add(:base, "This room is already booked for the selected time slot.")
    end
  end
end
