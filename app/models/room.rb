class Room < ApplicationRecord
  # Relationships
  has_many :reservations

  # Slugs
  extend FriendlyId
  friendly_id :name, use: :slugged

  # Attachments
  has_one_attached :photo

  # Predicates

  def available_now?
    start = Time.current.beginning_of_hour
    reservations.all.map(&:datetime_in).index(start).blank?
  end

  # Class Methods

  def self.options_for_select
    Room.all.map do |room|
      [room.name, room.id]
    end
  end


  # Instance Methods

  def square_photo
    photo.variant(resize: "300x300")
  end

  def card_photo
    photo.variant(resize: "100x180")
  end

  def reserved_hours
    # Return one datetime item per hour booked
    result = []
    reservations.each do |reservation|
      reservation.reserved_hours.each do |hour|
        result.push(hour)
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
