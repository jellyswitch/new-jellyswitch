
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
#  reservation_id   :bigint(8)
#  stripe_charge_id :string
#  user_id          :integer          not null
#
# Indexes
#
#  index_day_passes_on_billable_type_and_billable_id  (billable_type,billable_id)
#  index_day_passes_on_location_id                    (location_id)
#  index_day_passes_on_operator_id                    (operator_id)
#  index_day_passes_on_reservation_id                 (reservation_id)
#
# Foreign Keys
#
#  fk_rails_...  (reservation_id => reservations.id) ON DELETE => nullify
#

class DayPass < ApplicationRecord
  include HasLocation

  # Relationships
  belongs_to :billable, polymorphic: true
  belongs_to :day_pass_type
  belongs_to :invoice, optional: true
  belongs_to :user
  belongs_to :operator
  belongs_to :reservation, optional: true
  acts_as_tenant :operator
  has_many :discount_redemptions, as: :discountable, dependent: :nullify

  # Set on historical imports to skip member-lifecycle side effects (welcome drip,
  # activity-feed entries) that should not fire for back-dated records.
  attr_accessor :imported

  # Scopes
  # A pass is bundle-sourced if a bundle redemption minted it (day_pass_id set).
  # Only DayPass-minting redemptions — door "entry" and reserve-time "reservation"
  # (ADR 0015) — set day_pass_id (guest/admin_restore don't), so the kind-agnostic
  # `day_pass_id IS NOT NULL` filter excludes both from day-pass revenue (bundle
  # money is recognized once at sale — ADR 0009).
  scope :bundle_sourced, -> {
    where(id: DayPassBundleRedemption.where.not(day_pass_id: nil).select(:day_pass_id))
  }
  scope :not_bundle_sourced, -> {
    where.not(id: DayPassBundleRedemption.where.not(day_pass_id: nil).select(:day_pass_id))
  }
  scope :today, -> { where(day: Time.current) }
  scope :for_day, -> (date) { where(day: date) }
  scope :purchased, -> { where(complimentary: [false, nil]) }
  scope :complimentary, -> { where(complimentary: true) }
  scope :last_30_days, -> { where('day > ?', 30.days.ago ) }
  scope :this_month, -> () { where("day > ?", Time.current.beginning_of_month) }
  scope :for_week, -> (week_start, week_end) { where('day > ? and day <= ?', week_start, week_end) }

  # A purchased (non-bundle-sourced) pass bought for a booking that was then
  # cancelled — still unused and today-or-future, so it can be re-dated onto a
  # new booking (ADR 0019). `not_bundle_sourced` excludes bundle mints, which
  # have their own lifecycle.
  scope :reusable_coverage, ->(today) {
    not_bundle_sourced
      .where("day >= ?", today)
      .joins(:reservation)
      .where(reservations: { cancelled: true })
  }

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
