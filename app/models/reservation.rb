# typed: false
# == Schema Information
#
# Table name: reservations
#
#  id          :bigint(8)        not null, primary key
#  cancelled   :boolean          default(FALSE), not null
#  datetime_in :datetime         not null
#  hours       :integer          default(1), not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  room_id     :integer          not null
#  user_id     :integer          not null
#

class Reservation < ApplicationRecord
  # Relationships
  belongs_to :room
  belongs_to :user

  validates_with ReservationValidator

  default_scope { where(cancelled: false) }
  scope :not_cancelled, ->() { where(cancelled: false) }
  scope :this_month, -> () { where("datetime_in > ?", Time.current.beginning_of_month) }
  scope :for_room, -> (room) { where(room_id: room.id) }
  
  def pretty_datetime
    datetime_in.strftime("%m/%d/%Y at %l:%M%P")
  end

  def self.for_time(time)
    select do |reservation|
      (reservation.datetime_in <= time) && (reservation.datetime_in + reservation.minutes.minutes > time)
    end.first
  end

  def self.for_time_inclusive(time)
    select do |reservation|
      (reservation.datetime_in <= time) && (reservation.datetime_in + reservation.minutes.minutes >= time)
    end.first
  end

  def room
    Room.unscoped { super }
  end

  def hours
    minutes.to_f / 60.0
  end
end
