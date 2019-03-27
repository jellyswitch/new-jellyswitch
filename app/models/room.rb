# == Schema Information
#
# Table name: rooms
#
#  id          :bigint(8)        not null, primary key
#  av          :boolean          default(FALSE), not null
#  capacity    :integer          default(1), not null
#  description :text
#  name        :string           not null
#  slug        :string
#  visible     :boolean          default(TRUE), not null
#  whiteboard  :boolean          default(FALSE), not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  operator_id :integer          default(1), not null
#
# Indexes
#
#  index_rooms_on_operator_id  (operator_id)
#

class Room < ApplicationRecord
  # Relationships
  has_many :reservations
  belongs_to :operator
  acts_as_tenant :operator

  # Scopes
  scope :visible, ->() { where(visible: true) }

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

  def has_photo?
    photo.attached?
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
    photo.variant(resize: "x200")
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

  def calendar
    cal = Icalendar::Calendar.new
    cal.x_wr_calname = "Reservations: #{name}"
    reservations.each do |reservation|
      cal.event do |e|
        e.dtstart = reservation.datetime_in
        e.dtend = reservation.datetime_in + 1.hour
        if reservation.user.present?
          e.summary = reservation.user.name
        else
          e.summary = "DELETED USER"
        end
        e.description = "#{reservation.user.name} has reserved #{name} for an hour."
      end
    end
    cal.publish
    cal
  end
end
