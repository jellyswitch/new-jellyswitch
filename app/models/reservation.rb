class Reservation < ApplicationRecord
  # Relationships
  belongs_to :room
  belongs_to :user

  validates_with ReservationValidator

  def pretty_datetime
    datetime_in.strftime("%m/%d/%Y at %l:%M%P")
  end

  def reserved_hours
    result = []
    result.push(datetime_in)
    (hours-1).times do |i|
      new_datetime = datetime_in + (i+1).hours
      result.push(new_datetime)
    end
    result
  end
end
