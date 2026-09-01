
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

  # Self-serve purchases/reschedules may only target dates within this window.
  # The web form's year dropdown made it easy to buy a pass for today's date
  # NEXT year (a real member paid $40 for 07/17/2027); a bounded window turns
  # that mis-tap into a friendly error. Admin flows are intentionally ungated.
  # Keep in step with Billing::DayPassBundles::ScheduleDay::HORIZON_DAYS.
  MAX_ADVANCE_DAYS = 90

  # Relationships
  belongs_to :billable, polymorphic: true
  belongs_to :day_pass_type
  belongs_to :invoice, optional: true
  belongs_to :user
  belongs_to :operator
  belongs_to :reservation, optional: true
  # Live office hold only — Reservation's default_scope hides a cancelled one,
  # so this naturally goes nil the moment the hold is released (ADR 0026).
  has_one :office_hold, class_name: "Reservation", foreign_key: :day_office_pass_id
  acts_as_tenant :operator
  has_many :discount_redemptions, as: :discountable, dependent: :nullify

  delegate :day_office?, to: :day_pass_type, allow_nil: true

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
  # >= — day is a DATE, so strict > against beginning_of_month (a midnight
  # timestamp) silently excluded passes dated the 1st for the whole month.
  scope :this_month, -> () { where("day >= ?", Time.current.beginning_of_month.to_date) }
  scope :for_week, -> (week_start, week_end) { where('day > ? and day <= ?', week_start, week_end) }

  # A purchased (non-bundle-sourced) pass bought for a booking that was then
  # cancelled — still unused and today-or-future, so it can be re-dated onto a
  # new booking (ADR 0019). `not_bundle_sourced` excludes bundle mints, which
  # have their own lifecycle.
  scope :reusable_coverage, ->(today) {
    # GOTCHA: Reservation has `default_scope { where(cancelled: false) }`, so a
    # JOIN on :reservation hides cancelled rows and this would always be empty.
    # Match the link via an UNSCOPED subquery of cancelled reservation ids.
    not_bundle_sourced
      .where("day >= ?", today)
      .where(reservation_id: Reservation.unscoped.where(cancelled: true).select(:id))
  }

  after_create :log_activity, unless: :imported
  after_create :enroll_user_in_welcome_drip, unless: :imported
  # Seed a day_pass interest tag from the purchase (ADR 0022). `unless: :imported`
  # excludes bundle redemptions, door/reserve burns, and historical imports.
  # after_create_COMMIT so a tag write can never roll back or 500 the sale.
  after_create_commit :record_purchase_interest, unless: :imported

  # The single release authority for every destroy path (refund rescind,
  # cancel-scheduled-day, console) — cancels the hold so the room is bookable
  # again immediately. The FK's ON DELETE SET NULL (see migration) is only a
  # backstop against an orphaned non-null column; it does NOT cancel the
  # reservation, so this callback is load-bearing, not redundant with it.
  #
  # before_destroy, not after_destroy: the FK's ON DELETE SET NULL fires as
  # part of the DELETE statement itself, so by after_destroy day_office_pass_id
  # is already nulled and office_hold can no longer find the row to cancel.
  #
  # reload_office_hold, not office_hold: an earlier read of `office_hold` in
  # this same request/object (e.g. a serializer touching it before a
  # controller destroys the pass) memoizes the association target. If that
  # read happened before the hold existed (or after it was already released
  # elsewhere), the cached nil would make this a silent no-op and leave a live
  # hold behind, blocking the room. reload_ forces a fresh query every time.
  before_destroy { DayOffices::ReleaseHold.call(reload_office_hold) }

  # Instance methods
  def log_activity
    Activity.log(user: user, kind: :day_pass, subject: self, operator: operator)
  end

  def record_purchase_interest
    InterestTag.record(user: user, product: "day_pass", source: "last_purchase") if user
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

  # A pass is "used" once the member actually entered on its day — any door
  # punch or check-in at the pass's location that calendar day. Walk-in
  # purchases auto-check-in at purchase, so they lock immediately.
  def used?
    tz = ActiveSupport::TimeZone[location&.time_zone.presence || "UTC"] || Time.zone
    day_range = tz.local(day.year, day.month, day.day).all_day
    user.checkins.where(location_id: location_id, datetime_in: day_range).exists? ||
      user.door_punches.joins(:door)
          .where(doors: { location_id: location_id }, created_at: day_range)
          .exists?
  end

  # Reschedule policy: any unused pass can move to today or a future date —
  # even one whose day already slipped by ("I paid, I never came").
  def reschedulable?
    !used?
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
