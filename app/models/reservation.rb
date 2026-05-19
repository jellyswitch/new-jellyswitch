# == Schema Information
#
# Table name: reservations
#
#  id          :bigint(8)        not null, primary key
#  cancelled   :boolean          default(FALSE), not null
#  credit_cost :integer          default(0), not null
#  datetime_in :datetime         not null
#  hours       :integer          default(1), not null
#  minutes     :integer          default(0), not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  room_id     :integer          not null
#  user_id     :integer          not null
#  ended_early :boolean          default(FALSE)
#  paid        :boolean          default(null)

class Reservation < ApplicationRecord
  # Relationships
  belongs_to :room
  belongs_to :user
  belongs_to :recurring_reservation, optional: true
  has_and_belongs_to_many :amenities
  has_many :discount_redemptions, as: :discountable, dependent: :nullify

  validates_with ReservationValidator

  default_scope { where(cancelled: false) }
  scope :not_cancelled, ->() { where(cancelled: false) }
  scope :this_month, ->() { where("datetime_in > ?", Time.current.beginning_of_month) }
  scope :for_room, ->(room) { where(room_id: room.id) }
  scope :for_week, ->(week_start, week_end) { where("datetime_in > ? and datetime_in <= ?", week_start, week_end) }
  scope :for_day, ->(day) { where(datetime_in: day.beginning_of_day..day.end_of_day) }
  scope :today, ->() { where(datetime_in: Time.current.beginning_of_day..Time.current.end_of_day) }
  scope :future, ->() { where("datetime_in >= ?", Time.current) }
  scope :past, ->() { where("datetime_in < ?", Time.current) }
  scope :between, ->(time_start, time_end) { where("datetime_in > ? and datetime_in < ?", time_start, time_end) }
  scope :ongoing, -> { where('datetime_in < ? AND datetime_in + minutes * interval \'1 minute\' > ?', Time.current, Time.current) }
  scope :overlapping, ->(start_time, end_time) {
          where("datetime_in < ? AND (datetime_in + minutes * interval '1 minute') > ?", end_time, start_time)
        }
  scope :for_location_id, ->(location_id) { location_id ? joins(:room).where(rooms: { location_id: location_id }) : all }

  delegate :operator, :location, to: :room

  after_create :log_activity

  def log_activity
    Activity.log(user: user, kind: :reservation, subject: self)
  end

  def to_activity_payload
    {
      "room_name" => room&.name,
      "location_name" => room&.location&.name,
      "datetime_in" => datetime_in&.iso8601,
      "minutes" => minutes,
    }
  end

  REMINDER_OFFSET_MINUTES = 10.minutes.freeze

  def pretty_datetime
    datetime_in.strftime("%m/%d/%Y at %l:%M%P")
  end

  # datetime_in is a `timestamp with time zone` UTC instant; by default Rails
  # renders it in Time.zone (UTC on Heroku), which makes every .strftime and
  # .to_date elsewhere return UTC wall-clock — wrong for display. Auto-convert
  # to the reservation's location zone so callers don't have to thread it.
  # Comparisons and arithmetic still work because the underlying UTC instant
  # is preserved across the in_time_zone call.
  def datetime_in
    raw = super
    return raw if raw.nil?
    raw.in_time_zone(room&.location&.time_zone.presence || 'UTC')
  end

  def self.for_time(time)
    select do |reservation|
      !reservation.cancelled && (reservation.datetime_in <= time) && (reservation.datetime_in + reservation.minutes.minutes > time)
    end.first
  end

  def self.for_time_inclusive(time)
    select do |reservation|
      !reservation.cancelled && (reservation.datetime_in <= time) && (reservation.datetime_in + reservation.minutes.minutes >= time)
    end.first
  end

  def room
    Room.unscoped { super }
  end

  def hours
    minutes.to_f / 60.0
  end

  def datetime_out
    datetime_in + minutes.minutes
  end

  def ongoing?
    now = Time.current
    now >= start_at && now < start_at + minutes.minutes
  end

  def future?
    start_at > Time.current
  end

  # datetime_in is stored as `timestamp without time zone` but the stored
  # wall-clock is actually the location's local time. Read it back through the
  # location's TZ so comparisons against Time.current land on the right instant.
  def start_at
    tz = room&.location&.time_zone.presence || 'UTC'
    ActiveSupport::TimeZone[tz].local_to_utc(datetime_in)
  end

  def room_price
    room_price = paid? ? ((room.hourly_rate_in_cents / 60.0) * minutes).to_i : 0
  end

  def additional_duration_price(duration_minutes)
    room_price = paid? ? ((room.hourly_rate_in_cents / 60.0) * duration_minutes).to_i : 0
  end

  def amenity_price
    if user.should_charge_for_reservation?(room.location, datetime_in.to_date)
      amenity_price = Money.from_amount(amenities.sum(:price), "USD").cents
    else
      amenity_price = Money.from_amount(amenities.sum(:membership_price), "USD").cents
    end
  end

  def charge_amount
    room_price + amenity_price
  end

  def charge_description
    "#{room.location.operator.name} room reservation for #{pretty_datetime}"
  end

  def is_charged?
    !user.admin_or_manager?(room.location) && Invoice.where("created_at >= ? AND amount_due > 0", self.created_at).where(billable_type: "User", billable_id: user.id).select { |invoice| invoice.description == self.charge_description }.any?
  end

  def end_now!
    # End-early is a "release the room" action only — billing already
    # captured at start (or will at start, if the user end_now's
    # something they booked just before that captured). Shortening
    # minutes flips ongoing? to false so the room frees up immediately
    # for the next member; the captured charge stays at the booked
    # amount (the slot was held against other members regardless).
    actual_duration = [(Time.current - datetime_in) / 60, minutes].min.floor
    update(minutes: actual_duration, ended_early: true)
    true
  end

  def amenity_names
    amenities.pluck(:name).join(", ")
  end

  def part_of_series?
    recurring_reservation_id.present?
  end
end
