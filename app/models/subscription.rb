# == Schema Information
#
# Table name: subscriptions
#
#  id                                  :bigint(8)        not null, primary key
#  active                              :boolean          default(TRUE), not null
#  billable_type                       :string
#  cancelling_at_end_of_billing_period :boolean          default(FALSE), not null
#  paused                              :boolean          default(FALSE), not null
#  pending                             :boolean          default(FALSE), not null
#  start_date                          :date             not null
#  subscribable_type                   :string
#  created_at                          :datetime         not null
#  updated_at                          :datetime         not null
#  billable_id                         :bigint(8)
#  plan_id                             :integer          not null
#  stripe_subscription_id              :string
#  subscribable_id                     :bigint(8)
#
# Indexes
#
#  index_subscriptions_on_billable_type_and_billable_id          (billable_type,billable_id)
#  index_subscriptions_on_subscribable_type_and_subscribable_id  (subscribable_type,subscribable_id)
#

class Subscription < ApplicationRecord
  # Callbacks
  before_destroy :check_for_stripe_subscription
  after_create :log_subscription_started
  # after_create_COMMIT so a tag write can never roll back the subscription.
  after_create_commit :record_membership_interest
  after_create_commit :clear_churn_suppression
  after_update :log_subscription_ended_if_deactivated

  # Relationships
  belongs_to :plan
  belongs_to :billable, polymorphic: true
  belongs_to :subscribable, polymorphic: true
  has_many :office_leases
  has_many :discount_redemptions, as: :discountable, dependent: :nullify

  # Scopes
  scope :active, -> { where(active: true) }
  scope :pending, -> { where(pending: true) }
  # Subscriptions eligible for a renewal reminder. Excludes those scheduled to
  # cancel at period end -- those stay active: true until the period ends, so
  # without this filter they'd wrongly get "your membership renews soon."
  scope :renewal_reminder_candidates, -> { where(active: true, cancelling_at_end_of_billing_period: false) }
  scope :for_operator, ->(operator) { joins(:plan).where(plans: { operator_id: operator.id }) }
  scope :for_location, ->(location) do
          joins(:plan).where(plans: { id: Plan.for_location(location).map(&:id) })
        end
  scope :for_week, ->(week_start, week_end) { where("created_at > ? and created_at <= ?", week_start, week_end) }
  # Memberships only — office leases excluded. A subscribable may legitimately
  # hold several leases at once (an org renting three offices), so anything
  # backed by a lease plan or an actual OfficeLease is not a membership.
  # NULL subscription_ids are filtered out of the subquery on purpose: a
  # `NOT IN` list containing NULL matches nothing at all in SQL.
  scope :memberships, -> {
          joins(:plan)
            .where.not(plans: { plan_type: "lease" })
            .where.not(id: OfficeLease.where.not(subscription_id: nil).select(:subscription_id))
        }

  accepts_nested_attributes_for :plan

  delegate :operator, :location, to: :subscribable

  # Instance methods
  # Default `prorate: false` per ops policy: cancellations end access but
  # do not refund unused days of the current billing period.
  def cancel_stripe!(prorate: false)
    sub = stripe_subscription
    return unless sub
    sub.delete(prorate: prorate)
  end

  def set_stripe_to_cancel!
    sub = stripe_subscription
    return unless sub
    sub.save(cancel_at_period_end: true)
  end

  def has_stripe_subscription?
    stripe_subscription_id.present? && stripe_subscription.id.present?
  rescue StandardError => e
    false
  end

  def stripe_subscription
    if pending? || stripe_subscription_id.blank?
      nil
    else
      Stripe::Subscription.retrieve(self.stripe_subscription_id, {
        api_key: plan.location.stripe_secret_key,
        stripe_account: plan.location.stripe_user_id,
      })
    end
  rescue Stripe::InvalidRequestError => e
    Honeybadger.notify(e)
    nil
  end

  def pretty_datetime
    updated_at.strftime("%m/%d/%Y at %l:%M%P")
  end

  def check_for_stripe_subscription
    if stripe_subscription_id.present? && active?
      raise "Cancel Stripe Subscription first: #{stripe_subscription_id}"
    end
  end

  def pretty_name
    if plan.present?
      plan.pretty_name
    else
      "error"
    end
  end

  # ---- Day Pool (per-plan monthly day limit) ----------------------------
  # A "day used" is a calendar day on which the member opened the door (a door
  # punch) at the plan's location, counted within the current billing period,
  # net of admin-granted comp days. Reservations/check-ins never burn a day.
  # Exhausting the pool gates BUILDING ACCESS only — it does not revoke
  # membership identity (see app/models/concerns/permissions.rb). That coupling
  # was the bug behind the 2020 `return true` workaround; see ADR 0004.

  # The location the day limit is scoped to. A door punch resolves to a
  # location via its door, so the pool only counts entries at this location.
  def day_pool_location
    plan.location
  end

  # Distinct door-punch days at the plan's location within the current billing
  # period, minus comp days, floored at 0.
  def day_pool_used
    return 0 unless plan.has_day_limit? && subscribable.is_a?(User) && day_pool_location
    period_start, period_end = current_billing_period
    return 0 unless period_start

    # group_by_day fills the date range with zero-count entries for gap days,
    # so reject the empties before counting distinct days (mirrors UsageReport).
    punch_days = subscribable.door_punches
                             .joins(:door)
                             .where(doors: { location_id: day_pool_location.id })
                             # Room Entries are not building entries (ADR 0021) — only Building
                             # Door punches burn Day Pool days.
                             .where(room_entry: false)
                             .where(created_at: period_start...period_end)
                             .group_by_day("door_punches.created_at").count
                             .count { |_day, n| n.positive? }

    comps = CompDay.for_period(period_start, period_end)
                   .where(user_id: subscribable_id, location_id: day_pool_location.id)
                   .count

    [punch_days - comps, 0].max
  rescue StandardError => e
    0 # fail open: never lock a paying member out over a counting error
  end

  # Days remaining in the pool, floored at 0 — for display / API.
  def day_pool_remaining
    [plan.day_limit - day_pool_used, 0].max
  end
  alias_method :days_left, :day_pool_remaining

  # Building-access gate: does the member have a day left to enter today?
  # Same-day re-entry is always free (today is already a counted day).
  def has_days_left?(now = Time.current)
    return true unless plan.has_day_limit?
    return true unless subscribable.is_a?(User)
    return true if used_day_today?(now)
    day_pool_remaining > 0
  end

  # Did the member already open the door at the plan's location today? Used so
  # a member who hits their cap mid-day is not locked out on re-entry.
  def used_day_today?(now = Time.current)
    return false unless day_pool_location
    subscribable.door_punches
                .joins(:door)
                .where(doors: { location_id: day_pool_location.id })
                # Room Entries are not building entries (ADR 0021) — only Building
                # Door punches burn Day Pool days.
                .where(room_entry: false)
                .where(created_at: now.beginning_of_day..now.end_of_day)
                .exists?
  rescue StandardError => e
    false
  end

  def current_billing_period
    return monthly_anniversary_window unless has_stripe_subscription?

    sub = stripe_subscription
    [Time.at(sub.current_period_start), Time.at(sub.current_period_end)]
  rescue StandardError => e
    monthly_anniversary_window
  end

  # The billing-period window CONTAINING `date`. For the current period this is
  # exactly current_billing_period; for other periods it rolls the monthly
  # window from the current anchor. Lets usage be attributed to the period a
  # reservation FALLS IN, so booking for next month draws from next month's
  # fresh pool rather than the current (possibly exhausted) one.
  def billing_period_for(date = Time.current)
    cur_start, cur_end = current_billing_period
    return monthly_anniversary_window(date) unless cur_start
    return [cur_start, cur_end] if date >= cur_start && date < cur_end

    start = cur_start
    start -= 1.month while date < start
    start += 1.month while date >= start + 1.month
    [start, start + 1.month]
  end

  # Non-Stripe (comp/manual) subscriptions have no Stripe billing cycle, so
  # derive the CURRENT monthly window from the start_date day-of-month
  # anniversary. Previously this returned [start_date, Time.current] — an
  # ever-growing window that let a comped member's "monthly" meeting-room
  # allowance accumulate from signup forever instead of resetting each month.
  def monthly_anniversary_window(now = Time.current)
    period_start = start_date.to_time.beginning_of_day
    period_start += 1.month while period_start + 1.month <= now
    [period_start, period_start + 1.month]
  end

  # The end of the member's CURRENT commitment term — the first term boundary
  # after `now`, walking forward by the full commitment_duration from start_date.
  # Because a commitment re-arms each term (ADR 0005), this advances across
  # renewals (term 2's end once term 1 has passed, etc.). nil if no commitment.
  def commitment_term_end(now = Time.current)
    return nil unless plan.has_commitment_interval?
    term = plan.commitment_duration
    boundary = start_date.to_time.beginning_of_day + term
    boundary += term while boundary <= now
    boundary
  end

  # Is the member currently inside a (re-arming) commitment term?
  def in_commitment?(now = Time.current)
    e = commitment_term_end(now)
    e.present? && e > now
  end

  # Does this subscription back an office lease (a fixed-term contract)?
  # Members must not be able to self-cancel or downgrade these from the app —
  # only an admin terminates a lease via the office-lease flow. Keys on either
  # the lease-type plan or an actual OfficeLease record so a mistyped plan
  # can't slip a real lease through.
  def backs_office_lease?
    office_leases.exists? || plan&.lease? || false
  end

  DUPLICATE_MEMBERSHIP_MESSAGE =
    "This person already has an active membership. Switch their existing plan instead of adding a second one.".freeze

  # True when saving this would leave the subscribable holding two active
  # memberships — which means two Stripe subscriptions and two charges a month.
  #
  # Nothing used to check this, so a member who fired a second "Subscribe"
  # while the first was still in flight ended up billed for both (Aaron Squier,
  # 2026-06-24: Flex at 07:52:44 and Full Time at 07:52:46, two Stripe subs,
  # two welcome emails). Switching plans is a different path entirely —
  # SwitchMembership reuses the one Stripe subscription — so it never trips this.
  def duplicate_active_membership?
    return false if backs_office_lease?
    return false if subscribable_id.blank?

    scope = self.class.memberships.active.where(
      subscribable_type: subscribable_type,
      subscribable_id: subscribable_id,
    )
    scope = scope.where.not(id: id) if persisted?
    scope.exists?
  end

  # Member-initiated cancellation during a commitment: don't end immediately —
  # schedule the membership to end at the current term's boundary (Stripe
  # cancel_at), keeping access + billing through the term they committed to.
  # Admins bypass this and cancel immediately (see members_controller).
  def schedule_commitment_cancellation!
    set_end_date!(commitment_term_end)
    update!(cancelling_at_end_of_billing_period: true)
  end

  def has_end_date?
    sub = stripe_subscription
    sub.present? && sub.cancel_at.present?
  rescue StandardError => e
    false
  end

  def end_date
    sub = stripe_subscription
    return nil unless sub&.cancel_at
    Time.at(sub.cancel_at)
  end

  def set_end_date!(date)
    s = stripe_subscription
    return unless s
    s.cancel_at = date.to_i
    s.save
  end

  def has_canceled_at?
    sub = stripe_subscription
    sub.present? && sub.canceled_at.present?
  end

  def has_period_end?
    sub = stripe_subscription
    sub.present? && sub.current_period_end.present?
  end

  def current_period_end
    sub = stripe_subscription
    return nil unless sub&.current_period_end
    Time.at(sub.current_period_end)
  end

  def canceled_at
    sub = stripe_subscription
    return nil unless sub&.canceled_at
    Time.at(sub.canceled_at)
  end

  def ended_at
    sub = stripe_subscription
    return nil unless sub&.ended_at
    Time.at(sub.ended_at)
  end

  def log_subscription_started
    return unless subscribable.is_a?(User)
    Activity.log(user: subscribable, kind: :subscription_started, subject: self)
  end

  # Seed a membership interest tag from the purchase (ADR 0022). Only individual
  # member subs — not org subs (subscribable isn't a User) and not office-lease
  # subs (those are an office signal, and the lease culls the office tag anyway).
  def record_membership_interest
    return unless subscribable.is_a?(User)
    return if plan&.lease?
    InterestTag.record(user: subscribable, product: "membership", source: "last_purchase")
  end

  # A churn suppression ("Churned: …", set when the member cancelled as a
  # mover/visitor) is a prediction that they're gone for good — subscribing
  # again falsifies it, so clear it or the returned member misses every
  # campaign forever. Machine-set ("Churned:") only; admin-set suppressions
  # ("Suppressed by admin", bounce/complaint) are never touched.
  def clear_churn_suppression
    return unless subscribable.is_a?(User)
    return unless subscribable.marketing_suppressed? &&
                  subscribable.marketing_suppressed_reason.to_s.start_with?("Churned:")

    subscribable.update_columns(marketing_suppressed: false,
                                marketing_suppressed_reason: nil,
                                updated_at: Time.current)
  end

  def log_subscription_ended_if_deactivated
    return unless subscribable.is_a?(User)
    return unless saved_change_to_active?(from: true, to: false)
    Activity.log(user: subscribable, kind: :subscription_ended, subject: self)
  end

  def to_activity_payload
    {
      "plan_name" => plan&.pretty_name,
      "start_date" => start_date&.iso8601,
      "location_name" => plan&.location&.name,
    }
  end
end
