# == Schema Information
#
# Table name: reservations
#
#  id          :bigint(8)        not null, primary key
#  user_id     :integer          not null
#  datetime_in :datetime         not null
#  hours       :integer          default(1), not null
#  room_id     :integer          not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#

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
