
# == Schema Information
#
# Table name: day_passes
#
#  id               :bigint(8)        not null, primary key
#  billable_type    :string
#  complimentary    :boolean          default(FALSE), not null
#  day              :date             not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  billable_id      :bigint(8)
#  day_pass_type_id :integer
#  invoice_id       :integer
#  location_id      :integer
#  operator_id      :integer          default(1), not null
#  stripe_charge_id :string
#  user_id          :integer          not null
#
# Indexes
#
#  index_day_passes_on_billable_type_and_billable_id  (billable_type,billable_id)
#  index_day_passes_on_location_id                    (location_id)
#  index_day_passes_on_operator_id                    (operator_id)
#

class DayPass < ApplicationRecord
  include HasLocation

  # Relationships
  belongs_to :billable, polymorphic: true
  belongs_to :day_pass_type
  belongs_to :invoice, optional: true
  belongs_to :user
  belongs_to :operator
  acts_as_tenant :operator
  has_many :discount_redemptions, as: :discountable, dependent: :nullify

  # Set on historical imports to skip member-lifecycle side effects (welcome drip,
  # activity-feed entries) that should not fire for back-dated records.
  attr_accessor :imported

  # Scopes
  scope :today, -> { where(day: Time.current) }
  scope :for_day, -> (date) { where(day: date) }
  scope :purchased, -> { where(complimentary: [false, nil]) }
  scope :complimentary, -> { where(complimentary: true) }
  scope :last_30_days, -> { where('day > ?', 30.days.ago ) }
  scope :this_month, -> () { where("day > ?", Time.current.beginning_of_month) }
  scope :for_week, -> (week_start, week_end) { where('day > ? and day <= ?', week_start, week_end) }

  after_create :log_activity, unless: :imported
  after_create :enroll_user_in_welcome_drip, unless: :imported

  # Instance methods
  def log_activity
    Activity.log(user: user, kind: :day_pass, subject: self, operator: operator)
  end

  # Auto-enroll the day-passer in the Welcome Drip. Idempotent — no-op if
  # the user is already a member or already enrolled. Phase 6.3 will gate
  # this with SpamGuard.
  def enroll_user_in_welcome_drip
    user&.enroll_in_welcome_drip!
  end

  def to_activity_payload
    {
      "day" => day&.iso8601,
      "day_pass_type_name" => day_pass_type_name,
      "location_name" => location&.name,
      "complimentary" => complimentary,
    }
  end

  def pretty_day
    day.strftime("%m/%d/%Y")
  end

  def charge_description
    "#{operator.name} Day Pass for #{pretty_day}"
  end

  def today?
    day == Time.zone.today
  end

  def day_pass_type_name
    if day_pass_type.present?
      day_pass_type.name
    else
      "Unknown"
    end
  end

  def subscribable
    user
  end
end
