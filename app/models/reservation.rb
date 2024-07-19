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
  has_and_belongs_to_many :amenities

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

  delegate :operator, to: :room

  REMINDER_OFFSET_MINUTES = 10.minutes.freeze

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

  def datetime_out
    datetime_in + minutes.minutes
  end

  def ongoing?
    Time.zone.now.between?(datetime_in, datetime_out)
  end

  def future?
    datetime_in > Time.zone.now
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
    !user.admin_or_manager? && Invoice.where("created_at >= ? AND amount_due > 0", self.created_at).where(billable_type: "User", billable_id: user.id).select { |invoice| invoice.description == self.charge_description }.any?
  end

  def end_now!
    actual_duration = [(Time.current - datetime_in) / 60, minutes].min.floor
    update(minutes: actual_duration, ended_early: true)
  end

  def amenity_names
    amenities.pluck(:name).join(", ")
  end
end
