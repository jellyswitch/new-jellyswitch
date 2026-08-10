# == Schema Information
#
# Table name: reservations
#
#  id                         :bigint(8)        not null, primary key
#  attendee_count             :integer
#  authorized_amount_in_cents :integer
#  cancelled                  :boolean          default(FALSE), not null
#  captured_amount_in_cents   :integer
#  captured_at                :datetime
#  credit_cost                :integer          default(0), not null
#  datetime_in                :timestamptz      not null
#  ended_early                :boolean          default(FALSE)
#  hours                      :integer          default(1), not null
#  minutes                    :integer          default(0), not null
#  note                       :text
#  paid                       :boolean
#  payment_failed_at          :datetime
#  created_at                 :datetime         not null
#  updated_at                 :datetime         not null
#  recurring_reservation_id   :bigint(8)
#  room_id                    :integer          not null
#  stripe_payment_intent_id   :string
#  user_id                    :integer          not null
#
# Indexes
#
#  index_reservations_on_recurring_reservation_id  (recurring_reservation_id)
#  index_reservations_on_stripe_payment_intent_id  (stripe_payment_intent_id) UNIQUE
#

class Reservation < ApplicationRecord
  # Relationships
  belongs_to :room
  belongs_to :user
  belongs_to :recurring_reservation, optional: true
  # The day-office pass whose purchase MINTED this reservation as a hold (ADR
  # 0026) — nil for every ordinary booking. optional: true because the FK is
  # only ever set on that one reservation-per-pass path.
  belongs_to :day_office_pass, class_name: "DayPass", optional: true
  has_and_belongs_to_many :amenities
  has_many :discount_redemptions, as: :discountable, dependent: :nullify
  # Booking-capture + extension-delta invoices (ADR 0010/0011). A cancel refunds
  # all of them. nullify on destroy keeps the financial record after the
  # reservation row goes away.
  has_many :invoices, dependent: :nullify

  validates_with ReservationValidator

  # Optional attendee count a member can enter when booking a paid meeting room
  # (shown to admins in the activity feed). If given, it must be a positive whole
  # number that doesn't exceed the room's capacity.
  validates :attendee_count, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validate :attendee_count_within_capacity

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
  # after_create_COMMIT so a tag write can never roll back the booking.
  after_create_commit :record_meeting_room_interest

  def log_activity
    Activity.log(user: user, kind: :reservation, subject: self)
  end

  # Seed a meeting_room interest tag from a PAID meeting-room booking (ADR 0022).
  # Gate on the room being paid — NOT reservation.paid, which is false when a
  # member/staff books a paid room and true for free call-room overages.
  def record_meeting_room_interest
    return if day_office_pass_id.present? # an office hold is not meeting-room interest (ADR 0026)
    return unless user && room&.paid_room?
    InterestTag.record(user: user, product: "meeting_room", source: "last_purchase")
  end

  def attendee_count_within_capacity
    return if attendee_count.blank? || room.nil?

    if attendee_count > room.capacity
      errors.add(:attendee_count, "can't exceed the room's capacity of #{room.capacity}")
    end
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

  # "10:00–11:00 AM" in the room's location zone (datetime_in's reader already
  # presents the location zone). Drops the duplicate meridiem when both ends
  # share it. Used by ReservationValidator's overlap message and the API's
  # 409 conflict payload.
  def window_label
    starts = datetime_in
    ends = datetime_out
    if starts.strftime("%p") == ends.strftime("%p")
      "#{starts.strftime('%-l:%M')}–#{ends.strftime('%-l:%M %p')}"
    else
      "#{starts.strftime('%-l:%M %p')}–#{ends.strftime('%-l:%M %p')}"
    end
  end

  def ongoing?
    now = Time.current
    now >= start_at && now < start_at + minutes.minutes
  end

  # Whether `at` falls inside this reservation's building-access window (ADR
  # 0013): from `building_access_window_minutes` before start to the same after
  # end. datetime_in/out are absolute instants, so this comparison is
  # zone-correct without any tz math. Pass window_minutes to avoid loading the
  # operator per-record (the door path already has it).
  def access_window_open?(at = Time.current, window_minutes: nil)
    minutes_window = (window_minutes || room&.location&.operator&.building_access_window_minutes || 60).to_i
    window = minutes_window.minutes
    (datetime_in - window) <= at && at <= (datetime_out + window)
  end

  # The operator's door-access window width (ADR 0013), read the SAME way as
  # access_window_open? above and the Phase 6 arrival push, so the member-facing
  # "you can get in from…" promise can't drift from when the door actually opens.
  def building_access_window_minutes
    (room&.location&.operator&.building_access_window_minutes || 60).to_i
  end

  # The instant door access opens for this reservation. datetime_in is presented
  # in the location zone, so this stays room-local for a member-facing label.
  def access_opens_at
    datetime_in - building_access_window_minutes.minutes
  end

  def future?
    start_at > Time.current
  end

  # `datetime_in` is a timestamptz (a true UTC instant). The reader above
  # presents it in the location zone without changing the instant; this
  # re-derivation round-trips to the same absolute instant and exists only
  # for callers that want the zone made explicit.
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

  # The MAX amount to authorize (hold) at booking, in cents: the room/overage
  # base plus amenity add-ons. For a paid room, overage_cents is nil and
  # charge_amount already carries room+amenity. For a free room with a plan/
  # day-pass overage, room_price is 0 so charge_amount carries only the
  # amenity, and the overage rides on top. (Overage and a paid room are
  # mutually exclusive.) CaptureHold settles the actual amount via
  # ChargeCalculator, capped at this hold.
  def authorizable_charge_in_cents(overage_cents: nil)
    overage_cents.to_i + charge_amount
  end

  # What this reservation actually costs the member, in cents — for display
  # (admin feed, receipts UI). `charge_amount` is derived from the room's
  # hourly rate, so it returns $0 for a free meeting room even when a day-pass
  # or subscription member is charged a meeting-room overage (the overage is
  # priced by ChargeCalculator and lives on the Stripe hold/capture, not the
  # room rate). Take the largest of the booked price, the authorized hold, the
  # settled capture, and a fresh ChargeCalculator estimate so overages show up
  # without under-reporting paid rooms (whose amenities live in charge_amount).
  def effective_charge_in_cents
    [
      charge_amount.to_i,
      authorized_amount_in_cents.to_i,
      captured_amount_in_cents.to_i,
      Billing::Reservations::ChargeCalculator.call(reservation: self, minutes: minutes).to_i,
    ].max
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

  # A Day Office hold: the $0 reservation minted BY a day-office pass purchase
  # (ADR 0026) — never charged, never drawing meeting-room allowances.
  def day_office_hold?
    day_office_pass_id.present?
  end
end
