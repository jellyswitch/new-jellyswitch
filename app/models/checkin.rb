
# == Schema Information
#
# Table name: checkins
#
#  id            :bigint(8)        not null, primary key
#  billable_type :string
#  datetime_in   :datetime         not null
#  datetime_out  :datetime
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  billable_id   :bigint(8)
#  invoice_id    :integer
#  location_id   :integer          not null
#  user_id       :integer          not null
#
# Indexes
#
#  index_checkins_on_billable_type_and_billable_id  (billable_type,billable_id)
#

class Checkin < ApplicationRecord
  include HasLocation

  belongs_to :billable, polymorphic: true
  belongs_to :invoice, optional: true
  belongs_to :user

  scope :open, -> { where(datetime_out: nil) }
  scope :for_location, -> (loc) { where(location_id: loc.id) }
  scope :for_operator, -> (op) { where(location_id: [op.locations.map(&:id)]) }
  scope :this_month, -> () { where("datetime_in > ?", Time.current.beginning_of_month) }
  scope :for_week, -> (week_start, week_end) { where('datetime_in > ? and datetime_in <= ?', week_start, week_end) }

  delegate :operator, to: :location

  after_create :log_activity

  def log_activity
    Activity.log(user: user, kind: :checkin, subject: self)
  end

  def to_activity_payload
    {
      "location_name" => location&.name,
      "datetime_in" => datetime_in&.iso8601,
    }
  end

  def charge_description
    "Hourly charge for #{location.name}"
  end

  def charge_amount
    (per_minute_charge_amount * minutes).to_i
  end

  def per_minute_charge_amount
    location.hourly_rate_in_cents.to_f / 60.0
  end

  def per_hour_charge_amount
    location.hourly_rate_in_cents
  end

  # datetime_in/out are `timestamp with time zone` UTC instants; by default
  # Rails renders in Time.zone (UTC on Heroku), making .strftime and .to_date
  # return UTC wall-clock. Auto-convert to the location zone so display and
  # day-math in callers work without threading the zone through.
  def datetime_in
    raw = super
    return raw if raw.nil?
    raw.in_time_zone(location&.time_zone.presence || 'UTC')
  end

  def datetime_out
    raw = super
    return raw if raw.nil?
    raw.in_time_zone(location&.time_zone.presence || 'UTC')
  end

  def seconds
    (datetime_out - datetime_in).to_i
  end

  def minutes
    (seconds.to_f / 1.minute).ceil
  end

  def hours
    (seconds.to_f / 1.hour).ceil
  end

  def open?
    datetime_out.blank?
  end

  def auto_checkout_time
    zone = ActiveSupport::TimeZone[location.time_zone]
    offset = zone.now.formatted_offset

    time_input = "#{location.working_day_end} #{offset}"

    time = Time.strptime(time_input, "%k:%M %Z")
    time.change(day: datetime_in.day)
  end

  def subscribable
    user
  end
end
