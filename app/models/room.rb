class Room < ApplicationRecord
  # Relationships
  has_many :reservations

  # Slugs
  extend FriendlyId
  friendly_id :name, use: :slugged

  def self.options_for_select
    Room.all.map do |room|
      [room.name, room.id]
    end
  end

  def reserved_hours
    # Return one datetime item per hour booked
    result = []
    reservations.each do |reservation|
      result.push(reservation.datetime_in)
      (reservation.hours-1).times do |i|
        new_datetime = reservation.datetime_in + (i+1).hours
        result.push(new_datetime)
      end
    end
    result
  end

  def availability_for_day(day_start)
    reserved = reserved_hours
    result = []
    24.times do |i|
      hour = day_start + i.hours
      is_reserved = reserved.index(hour).present?
      result.push({hour: hour, reserved: is_reserved})
    end
    result
  end
end
