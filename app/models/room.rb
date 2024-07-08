# == Schema Information
#
# Table name: rooms
#
#  id                                 :bigint(8)        not null, primary key
#  allow_shorter_reservation_duration :boolean          default(TRUE), not null
#  av                                 :boolean          default(FALSE), not null
#  capacity                           :integer          default(1), not null
#  credit_cost                        :integer          default(0), not null
#  description                        :text
#  hourly_rate_in_cents               :integer          default(0), not null
#  name                               :string           not null
#  rentable                           :boolean          default(FALSE), not null
#  slug                               :string
#  square_footage                     :integer          default(0), not null
#  visible                            :boolean          default(TRUE), not null
#  whiteboard                         :boolean          default(FALSE), not null
#  created_at                         :datetime         not null
#  updated_at                         :datetime         not null
#  location_id                        :bigint(8)
#  operator_id                        :integer          default(1), not null
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
  searchkick
  # Relationships
  has_many :reservations
  has_many :amenities, dependent: :destroy
  accepts_nested_attributes_for :amenities, reject_if: :all_blank

  belongs_to :operator
  acts_as_scopable :operator, :location
  belongs_to :location

  # Scopes
  scope :visible, ->() { where(visible: true) }
  scope :invisible, ->() { where(visible: false) }
  scope :rentable, ->() { where(rentable: true) }
  scope :cheapest, ->() { order("hourly_rate_in_cents DESC") }

  # Slugs
  extend FriendlyId
  friendly_id :name, use: :slugged

  # Attachments
  has_one_attached :photo

  def search_data
    {
      name: name,
      text: description,
    }
  end

  # Predicates

  def available_now?
    available_at?(Time.current.beginning_of_half_hour)
  end

  def available_at?(timestamp)
    reservations.for_time(timestamp.beginning_of_half_hour).blank?
  end

  def available?(start_time:, duration:)
    end_time = start_time.in_time_zone + duration.minutes

    !reservations.overlapping(start_time, end_time).exists?
  end

  def calculate_available_durations(start_time:)
    possible_durations = [30, 60, 90, 120, 180, 240, 480]
    available_durations = []

    possible_durations.each do |duration|
      if available?(start_time: start_time, duration: duration)
        available_durations << duration
      else
        break
      end
    end

    available_durations
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

  def self.unavailable(date: Date.current.to_s, time: Time.current.strftime("%I:%M"), duration: 30)
    start_time = Time.zone.parse("#{date} #{time}")
    end_time = (start_time + duration.to_i.minutes)

    Room.visible.left_joins(:reservations)
        .where("(reservations.datetime_in + make_interval(mins := reservations.minutes)) > ? AND reservations.datetime_in < ?", start_time, end_time)
        .distinct
  end

  def self.available(date: Date.current.to_s, time: Time.current.strftime("%H:%M"), duration: 30)
    unavailable_rooms = self.unavailable(date: date, time: time, duration: duration)
    Room.visible.where.not(id: unavailable_rooms.select(:id))
  end

  # Instance Methods

  def square_photo
    photo.variant(resize: "300x300")
  end

  def card_photo
    photo.variant(resize: "x200")
  end

  def availability_for_day(day_start)
    result = []

    48.times do |i|
      time = day_start + (i * 30).minutes
      reservation = reservations.for_time(time)
      result.push({
        hour: time,
        reservation: reservation,
      })
    end

    result
  end

  def future_availability_for_day(day_start)
    availability_for_day(day_start).select do |option|
      option[:hour] >= Time.current.beginning_of_half_hour
    end
  end

  def calendar
    cal = Icalendar::Calendar.new
    cal.x_wr_calname = "Reservations: #{name}"

    cal.timezone do |t|
      Time.use_zone(location.time_zone) do
        t.tzid = Time.zone.tzinfo.name
      end
    end

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

  def paid_room?
    rentable? && hourly_rate_in_cents > 0
  end
end
