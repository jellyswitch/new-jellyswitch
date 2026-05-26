# == Schema Information
#
# Table name: recurring_reservations
#
#  id                 :bigint(8)        not null, primary key
#  cancelled          :boolean          default(FALSE), not null
#  day_of_month       :integer
#  day_of_week        :integer
#  duration_minutes   :integer          not null
#  end_date           :date             not null
#  recurrence_pattern :string           not null
#  start_date         :date             not null
#  time_of_day        :time             not null
#  title              :string           not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  location_id        :bigint(8)
#  operator_id        :integer          not null
#  room_id            :integer          not null
#  user_id            :integer          not null
#
# Indexes
#
#  index_recurring_reservations_on_operator_id  (operator_id)
#  index_recurring_reservations_on_room_id      (room_id)
#  index_recurring_reservations_on_user_id      (user_id)
#
class RecurringReservation < ApplicationRecord
  belongs_to :user
  belongs_to :room
  belongs_to :operator
  belongs_to :location

  has_many :reservations, dependent: :nullify

  acts_as_tenant :operator

  validates :title, :recurrence_pattern, :duration_minutes, :time_of_day,
            :start_date, :end_date, presence: true
  validates :recurrence_pattern, inclusion: {
    in: %w[daily_weekdays weekly biweekly monthly]
  }
  validate :end_date_after_start_date

  scope :active, -> { where(cancelled: false) }
  scope :for_room, ->(room) { where(room_id: room.id) }

  PERIOD_OPTIONS = {
    "1 month" => 1,
    "3 months" => 3,
    "6 months" => 6,
    "1 year" => 12
  }.freeze

  PATTERN_OPTIONS = {
    "Daily (Weekdays)" => "daily_weekdays",
    "Weekly" => "weekly",
    "Biweekly" => "biweekly",
    "Monthly" => "monthly"
  }.freeze

  def occurrence_dates
    dates = []
    current = start_date

    while current <= end_date
      case recurrence_pattern
      when "daily_weekdays"
        dates << current if current.on_weekday?
      when "weekly"
        dates << current if current.wday == day_of_week
      when "biweekly"
        if current.wday == day_of_week
          week_diff = ((current - start_date).to_i / 7)
          dates << current if week_diff.even?
        end
      when "monthly"
        dates << current if current.day == (day_of_month || start_date.day)
      end
      current += 1.day
    end

    dates
  end

  def active_reservations
    reservations.where(cancelled: false)
  end

  def future_reservations
    reservations.future
  end

  def pattern_description
    case recurrence_pattern
    when "daily_weekdays" then "Every weekday"
    when "weekly" then "Every #{Date::DAYNAMES[day_of_week || 0]}"
    when "biweekly" then "Every other #{Date::DAYNAMES[day_of_week || 0]}"
    when "monthly" then "Monthly on the #{(day_of_month || start_date.day).ordinalize}"
    end
  end

  def time_description
    time_of_day.strftime("%l:%M %p").strip
  end

  def duration_description
    if duration_minutes >= 60
      hours = duration_minutes / 60
      mins = duration_minutes % 60
      mins > 0 ? "#{hours}h #{mins}m" : "#{hours} hour#{'s' if hours > 1}"
    else
      "#{duration_minutes} minutes"
    end
  end

  private

  def end_date_after_start_date
    if end_date.present? && start_date.present? && end_date <= start_date
      errors.add(:end_date, "must be after start date")
    end
  end
end
