# == Schema Information
#
# Table name: rooms
#
#  id                                 :bigint(8)        not null, primary key
#  allow_shorter_reservation_duration :boolean          default(TRUE), not null
#  archived                           :boolean          default(FALSE), not null
#  capacity                           :integer          default(1), not null
#  credit_cost                        :integer          default(0), not null
#  description                        :text
#  features                           :text             default([]), is an Array
#  hourly_rate_in_cents               :integer          default(0), not null
#  include_with_day_pass              :boolean          default(FALSE), not null
#  name                               :string           not null
#  rentable                           :boolean          default(FALSE), not null
#  slug                               :string
#  square_footage                     :integer          default(0), not null
#  visible                            :boolean          default(TRUE), not null
#  created_at                         :datetime         not null
#  updated_at                         :datetime         not null
#  location_id                        :bigint(8)
#  operator_id                        :integer          default(1), not null
#
# Indexes
#
#  index_rooms_on_archived     (archived)
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
  has_many :reservations, dependent: :destroy
  has_many :amenities, dependent: :destroy
  # Electric locks protecting this room (ADR 0021). Nullify, not destroy:
  # detaching a room's lock demotes the door to a Building Door.
  has_many :doors, dependent: :nullify
  accepts_nested_attributes_for :amenities, reject_if: :all_blank

  belongs_to :operator
  acts_as_scopable :operator, :location
  belongs_to :location

  # Validations — the admin room forms (web + mobile API) expose these
  # NOT NULL columns; a blank field typecasts to nil and used to reach
  # Postgres as a NotNullViolation 500 instead of a field error (Tahoe
  # Longhouse "Meeting Room", 2026-07-20). numericality allows nil so a
  # blank field reports only "can't be blank", not also "is not a number".
  validates :name, presence: true
  validates :capacity, :square_footage, :hourly_rate_in_cents, :credit_cost,
    presence: true,
    numericality: { only_integer: true, greater_than_or_equal_to: 0, allow_nil: true }

  # Scopes
  scope :active, -> { where(archived: [false, nil]) }
  scope :archived, -> { where(archived: true) }
  # `visible` and `rentable` chain the active filter so member-facing
  # paths never see archived rooms, regardless of caller.
  scope :visible, ->() { active.where(visible: true) }
  scope :invisible, ->() { active.where(visible: false) }
  scope :rentable, ->() { active.where(rentable: true) }
  # ADR 0019: rooms a not-yet-covered user may still book by committing day-pass
  # coverage at booking — cash-rentable rooms OR included rooms that a day pass
  # unlocks (rate 0 + include_with_day_pass). Widens the no-coverage room list so
  # the buy-a-day-pass confirm can surface, instead of hiding included rooms.
  scope :rentable_or_day_pass_included, ->() {
    active.where("rentable = ? OR (hourly_rate_in_cents = ? AND include_with_day_pass = ?)", true, 0, true)
  }
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
      operator_id: operator_id,
    }
  end

  # Door↔Room attachment (ADR 0021). Reassignment is scoped to this room's
  # location so a lock can never be attached across locations. Full-list
  # semantics: doors omitted from `door_ids` are detached (become Building
  # Doors again). Blank entries (the web form's hidden "clear all" input)
  # are ignored. Single home for the rule — the admin API and the operator
  # web form both call this.
  def reassign_doors!(door_ids, operator:)
    ids = Array(door_ids).reject(&:blank?).map(&:to_i)
    scope = Door.where(operator: operator, location: location)
    scope.where(room_id: id).where.not(id: ids).update_all(room_id: nil)
    scope.where(id: ids).update_all(room_id: id)
  end

  # Predicates

  def available_now?
    available_at?(Time.current.beginning_of_half_hour)
  end

  def available_at?(timestamp)
    reservations.for_time(timestamp.beginning_of_half_hour).blank?
  end

  # `except:` skips a reservation id from the overlap check — used when
  # editing a reservation so its own slot doesn't read as "taken".
  def available?(start_time:, duration:, except: nil)
    end_time = start_time.in_time_zone + duration.minutes

    scope = reservations.overlapping(start_time, end_time)
    scope = scope.where.not(id: except) if except.present?
    !scope.exists?
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

  def calculate_max_continuous_duration(start_time:, max_minutes: 480, step: 15)
    duration = 0
    while duration + step <= max_minutes
      break unless available?(start_time: start_time, duration: duration + step)
      duration += step
    end
    duration
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

  def self.unavailable(date: Date.current.to_s, time: Time.current.strftime("%I:%M"), duration: 30, include_hidden: false)
    start_time = Time.zone.parse("#{date} #{time}")
    end_time = (start_time + duration.to_i.minutes)

    base = include_hidden ? Room.active : Room.visible
    base.left_joins(:reservations)
        .where("(reservations.datetime_in + make_interval(mins := reservations.minutes)) > ? AND reservations.datetime_in < ?", start_time, end_time)
        .distinct
  end

  def self.available(date: Date.current.to_s, time: Time.current.strftime("%H:%M"), duration: 30, include_hidden: false)
    unavailable_rooms = self.unavailable(date: date, time: time, duration: duration, include_hidden: include_hidden)
    base = include_hidden ? Room.active : Room.visible
    base.where.not(id: unavailable_rooms.select(:id))
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

  # Booking-duration policy (2026-07 consistency fix: web admin allowed 8h
  # while mobile admin allowed 12h). Staff can book any room up to 12h on
  # every surface. Members and web visitors get 12h on PRICED rooms only
  # ("book the conference room for a day" — the hourly rate is the natural
  # brake); free/call rooms keep the 4h cap so an included-minutes plan
  # can't blanket-block them. Every duration UI and the API backstop read
  # from here — don't fork these numbers per surface again.
  ADMIN_MAX_BOOKING_MINUTES = 720
  PAID_ROOM_MAX_BOOKING_MINUTES = 720
  FREE_ROOM_MAX_BOOKING_MINUTES = 240

  def max_bookable_minutes(admin: false)
    return ADMIN_MAX_BOOKING_MINUTES if admin
    paid_room? ? PAID_ROOM_MAX_BOOKING_MINUTES : FREE_ROOM_MAX_BOOKING_MINUTES
  end

  # Whether this room draws from a booker's day-pass included-minutes bucket
  # (a "call room"). Explicit column as of ADR 0012 — previously inferred from
  # hourly_rate_in_cents == 0. Backfilled true for every $0 room.
  def counts_toward_day_pass?
    include_with_day_pass?
  end

  def has_av?
    amenities.exists?(name: Amenity::AV_EQUIPMENT)
  end

  def has_whiteboard?
    amenities.exists?(name: Amenity::WHITEBOARD)
  end

  # API serialization for the member-facing room card. Free amenities render as
  # informational chips (names only); priced amenities render as selectable
  # add-ons carrying both rates in cents. Rates are stored as float dollars.
  def amenity_add_ons
    amenities.add_ons.map do |a|
      {
        id: a.id,
        name: a.name,
        non_member_rate_cents: (a.price.to_f * 100).round,
        member_rate_cents: (a.membership_price.to_f * 100).round,
      }
    end
  end

  def amenity_feature_names
    amenities.features.map(&:name)
  end
end
