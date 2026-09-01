class DayPassBundle < ApplicationRecord
  class NoPassesRemaining < StandardError; end

  belongs_to :user
  belongs_to :day_pass_type
  belongs_to :location, optional: true
  belongs_to :operator
  belongs_to :billable, polymorphic: true, optional: true
  belongs_to :invoice, optional: true
  has_many :redemptions, class_name: "DayPassBundleRedemption", dependent: :destroy

  acts_as_tenant :operator

  # Buying a pack is a day_pass purchase signal (ADR 0022) — every create here is
  # a purchase (SaveBundle). There's no separate bundle interest product.
  # after_create_COMMIT so a tag write can never roll back the sale.
  after_create_commit :record_purchase_interest

  validates :quantity_purchased, :passes_remaining,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :active, -> { where("passes_remaining > 0").where("expires_at IS NULL OR expires_at > ?", Time.current) }

  # ADR 0018: a covered date may not exceed the bundle's expiration — a pass can
  # only be spent on a day the bundle survives. For a FUTURE date that means
  # expires_at must clear the whole target day; for TODAY, .active's "not
  # expired right now" is the whole rule — a bundle expiring later today must
  # still cover a same-day redeem/booking (Task 10). The single canonical
  # date-addressed eligibility filter: every path that spends or offers a pass
  # FOR A GIVEN DATE (ScheduleDay#eligible_bundle, RedeemBundlePass,
  # CoverageState, the rooms#pricing bundle_pass_redeemable flag) must use it,
  # or scheduling and booking disagree on which dates a pack covers. As-of-now
  # checks (door entry, balance displays) stay on .active.
  scope :usable_on, ->(date, tz) {
    today = Time.current.in_time_zone(tz).to_date
    scope = active
    scope = scope.where("expires_at IS NULL OR expires_at > ?", date.in_time_zone(tz).end_of_day) if date > today
    scope
  }

  after_create :log_activity

  # The pack purchase is its own timeline card. Each pass burned off it still
  # logs the usual day_pass activity — the bundle card is the rollup, not a
  # replacement, so staff can see "4 of 10 used" beside the individual days.
  def log_activity
    Activity.log(user: user, kind: :day_pass_bundle, subject: self, operator: operator)
  end

  # passes_remaining is deliberately absent: it moves after purchase, and the
  # timeline reads the live count through TimelineHoursIndex instead.
  def to_activity_payload
    {
      "quantity" => quantity_purchased,
      "day_pass_type_name" => day_pass_type&.name,
      "location_name" => location&.name,
    }
  end

  # Soonest-expiring first (NULLs/perpetual last), then oldest — "use it before
  # you lose it" (ADR 0018). The single canonical draw order: every caller that
  # picks "the" active bundle for a user/location (ScheduleDay#eligible_bundle,
  # Api::V1::DayPassesController#redeem_today's routing lookup, CoverageState
  # #active_bundle) must use this SAME order, or a routing decision made on one
  # order can disagree with a draw made on another (Task 10 fix).
  scope :draw_order, -> { order(Arel.sql("expires_at ASC NULLS LAST, created_at ASC")) }

  def record_purchase_interest
    InterestTag.record(user: user, product: "day_pass", source: "last_purchase") if user
  end

  def expired?
    expires_at.present? && expires_at <= Time.current
  end

  def active?
    passes_remaining.to_i > 0 && !expired?
  end

  # Spend one pass, logging a redemption. Atomic. kind is :entry | :guest |
  # :reservation | :admin_burn (staff spend, nothing minted; guest_name holds
  # the reason). entry/reservation redemptions also pass the minted DayPass
  # (and reservation links the booking that spent it); guest passes guest_name.
  # redeemed_at defaults to now; reserve-time burns stamp the reservation's start
  # so the once-per-business-day-window dedupe (which keys on redeemed_at) lines
  # up across the door and the booking — including future-dated reservations.
  def burn!(kind:, performed_by:, guest_name: nil, day_pass: nil, reservation: nil, redeemed_at: Time.current)
    with_lock { burn_locked!(kind: kind, performed_by: performed_by, guest_name: guest_name, day_pass: day_pass, reservation: reservation, redeemed_at: redeemed_at) }
  end

  # Assumes the caller already holds the row lock (with_lock). Decrements + logs.
  # reservation: links a booking-time burn (ADR 0015); redeemed_at lets reserve-time
  # burns stamp the reservation's start so the once-per-business-day-window dedupe
  # lines up across the door and the booking.
  # defer_review_email: when true, skip ONLY the follow_up branch (leave replenishment
  # as-is) — pass true when scheduling a FUTURE visit (ADR 0018), since the member
  # hasn't arrived yet, so "how was your visit?" must not fire until they do.
  # Returns the created DayPassBundleRedemption (and so does burn!, via with_lock).
  def burn_locked!(kind:, performed_by:, guest_name: nil, day_pass: nil, reservation: nil, redeemed_at: Time.current, defer_review_email: false)
    raise NoPassesRemaining if passes_remaining.to_i <= 0 || expired?
    update!(passes_remaining: passes_remaining - 1)
    redemption = redemptions.create!(operator: operator, kind: kind.to_s, performed_by: performed_by,
                                     guest_name: guest_name, day_pass: day_pass, reservation: reservation,
                                     redeemed_at: redeemed_at)
    enqueue_lifecycle_emails(kind, defer_review_email: defer_review_email)
    redemption
  end

  # Event-fired buyer emails (see CONTEXT.md / ADR 0009 family). The job gates
  # on the template being enabled and de-dupes per (bundle, email_type), so it
  # is safe to enqueue optimistically here.
  #   - review (follow_up): the holder's FIRST entry burn — "how was your visit?"
  #   - replenishment: the pass that empties the pack — "grab another / go unlimited"
  def enqueue_lifecycle_emails(kind, defer_review_email: false)
    if kind.to_s == "entry" && !defer_review_email && redemptions.where(kind: "entry").count == 1
      SendProductEmailJob.perform_later(self.class.name, id, operator_id, "day_pass_bundle", "follow_up", user_id)
    end

    if passes_remaining.to_i.zero?
      SendProductEmailJob.perform_later(self.class.name, id, operator_id, "day_pass_bundle", "replenishment", user_id)
    end
  end

  # Mirrors DayPass#subscribable — used by BillableFactory to resolve billable.
  def subscribable
    user
  end

  def charge_description
    "#{operator.name} #{day_pass_type.quantity}-Pack Day Pass Bundle"
  end

  # Give one pass back when UNDOING a booking-time burn (rollback / pre-coverage
  # cancel) — capped at the pack size so an interleaved admin_restore can't push
  # the count over quantity_purchased. Assumes the caller holds the row lock and
  # destroys the redemption + minted day pass itself.
  def refund_pass_locked!
    update!(passes_remaining: [passes_remaining.to_i + 1, quantity_purchased.to_i].min)
  end

  # Admin adds a pass back (auditable). reason is stored in guest_name to keep the table lean.
  # Returns false (no-op) if passes_remaining is already at quantity_purchased
  # (prevents over-credit) — callers should surface that instead of claiming success.
  def restore!(by:, reason: nil)
    with_lock { restore_locked!(by: by, reason: reason) }
  end

  # I1: shared restore logic — assumes the caller already holds the row lock.
  # kind controls the audit trail (e.g. "admin_restore", "schedule_cancel").
  # guest_name stores the reason/date in ISO form (no dedicated column).
  def restore_locked!(by:, reason: nil, kind: "admin_restore")
    return false if passes_remaining.to_i >= quantity_purchased.to_i
    update!(passes_remaining: passes_remaining + 1)
    redemptions.create!(operator: operator, kind: kind, performed_by: by,
                        guest_name: reason, redeemed_at: Time.current)
    true
  end

  # Zero the pack when its purchase invoice is refunded / voided — the bundle
  # counterpart of destroying a refunded DayPass row. The `.active` scope
  # (passes_remaining > 0) is the sole redemption/access gate, so zeroing is the
  # revoke that can't be missed. One admin_burn ledger row per rescinded pass
  # keeps the ledger 1:1 with decrements (reason in guest_name; performed_by nil
  # = system — the refund itself records who acted). Already-burned days stay
  # history. Deliberately NOT burn_locked!: a refunded buyer must not receive
  # the review / replenishment ("grab another pack") lifecycle emails.
  # Returns the number of passes rescinded (0 = nothing to do).
  def rescind_remaining!(reason:, by: nil)
    with_lock do
      count = passes_remaining.to_i
      if count > 0
        update!(passes_remaining: 0)
        count.times do
          redemptions.create!(operator: operator, kind: "admin_burn", performed_by: by,
                              guest_name: reason, redeemed_at: Time.current)
        end
      end
      count
    end
  end
end
