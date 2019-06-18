# == Schema Information
#
# Table name: rooms
#
#  id             :bigint(8)        not null, primary key
#  av             :boolean          default(FALSE), not null
#  capacity       :integer          default(1), not null
#  description    :text
#  name           :string           not null
#  slug           :string
#  square_footage :integer          default(0), not null
#  visible        :boolean          default(TRUE), not null
#  whiteboard     :boolean          default(FALSE), not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  location_id    :bigint(8)
#  operator_id    :integer          default(1), not null
#
# Indexes
#
#  index_rooms_on_location_id  (location_id)
#  index_rooms_on_operator_id  (operator_id)
#
# Foreign Keys
#
#  fk_rails_...  (location_id => locations.id)
#

class Room < ApplicationRecord
  # Relationships
  has_many :reservations
  belongs_to :operator
  acts_as_scopable :operator, :location
  belongs_to :location

  # Scopes
  scope :visible, ->() { where(visible: true) }
  scope :invisible, ->() { where(visible: false) }

  # Slugs
  extend FriendlyId
  friendly_id :name, use: :slugged

  # Attachments
  has_one_attached :photo

  # Predicates

  def available_now?
    available_at?(Time.current)
  end

  def available_at?(timestamp)
    hour = timestamp.beginning_of_hour
    reservations.all.map(&:datetime_in).index(hour).blank?
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
    result = []
    24.times do |i|
      hour = day_start + i.hours
      reservation = reservations.for_time(hour)
      result.push({
        hour: hour,
        reservation: reservation
      })
    end
    result
  end

  def future_availability_for_day(day_start)
    availability_for_day(day_start).select do |option|
      option[:hour].future?
    end
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
          e.description = "#{reservation.user.name} has reserved #{name} for an hour."
        else
          e.summary = "DELETED USER"
          e.description = "DELETED USER has reserved #{name} for an hour."
        end
      end
    end
    cal.publish
    cal
  end
end
