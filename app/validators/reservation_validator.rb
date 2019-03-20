class ReservationValidator < ActiveModel::Validator
  def validate(record)
    if record.cancelled?
      return true
    end
    record.reserved_hours.each do |attempt|
      overlap = record.room.reserved_hours.index(attempt).present?
      if overlap
        record.errors[:base] << "#{record.room.name} is reserved during this time"
      end
    end
  end
end