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

  validates :quantity_purchased, :passes_remaining,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :active, -> { where("passes_remaining > 0").where("expires_at IS NULL OR expires_at > ?", Time.current) }

  def expired?
    expires_at.present? && expires_at <= Time.current
  end

  def active?
    passes_remaining.to_i > 0 && !expired?
  end

  # Spend one pass, logging a redemption. Atomic. kind is :entry | :guest |
  # :reservation. entry/reservation redemptions also pass the minted DayPass
  # (and reservation links the booking that spent it); guest passes guest_name.
  # redeemed_at defaults to now; reserve-time burns stamp the reservation's start
  # so the once-per-business-day-window dedupe (which keys on redeemed_at) lines
  # up across the door and the booking — including future-dated reservations.
  def burn!(kind:, performed_by:, guest_name: nil, day_pass: nil, reservation: nil, redeemed_at: Time.current)
    with_lock { burn_locked!(kind: kind, performed_by: performed_by, guest_name: guest_name, day_pass: day_pass, reservation: reservation, redeemed_at: redeemed_at) }
  end

  # Assumes the caller already holds the row lock (with_lock). Decrements + logs.
  def burn_locked!(kind:, performed_by:, guest_name: nil, day_pass: nil, reservation: nil, redeemed_at: Time.current)
    raise NoPassesRemaining if passes_remaining.to_i <= 0 || expired?
    update!(passes_remaining: passes_remaining - 1)
    redemptions.create!(operator: operator, kind: kind.to_s, performed_by: performed_by,
                        guest_name: guest_name, day_pass: day_pass, reservation: reservation,
                        redeemed_at: redeemed_at)
    enqueue_lifecycle_emails(kind)
  end

  # Event-fired buyer emails (see CONTEXT.md / ADR 0009 family). The job gates
  # on the template being enabled and de-dupes per (bundle, email_type), so it
  # is safe to enqueue optimistically here.
  #   - review (follow_up): the holder's FIRST entry burn — "how was your visit?"
  #   - replenishment: the pass that empties the pack — "grab another / go unlimited"
  def enqueue_lifecycle_emails(kind)
    if kind.to_s == "entry" && redemptions.where(kind: "entry").count == 1
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
  # No-op if passes_remaining is already at quantity_purchased (prevents over-credit).
  def restore!(by:, reason: nil)
    with_lock do
      return if passes_remaining.to_i >= quantity_purchased.to_i
      update!(passes_remaining: passes_remaining + 1)
      redemptions.create!(operator: operator, kind: "admin_restore", performed_by: by,
                          guest_name: reason, redeemed_at: Time.current)
    end
  end
end
