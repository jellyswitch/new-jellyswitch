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

  # Spend one pass, logging a redemption. Atomic. kind is :entry | :guest.
  # entry redemptions also pass the minted DayPass; guest redemptions pass guest_name.
  def burn!(kind:, performed_by:, guest_name: nil, day_pass: nil)
    with_lock { burn_locked!(kind: kind, performed_by: performed_by, guest_name: guest_name, day_pass: day_pass) }
  end

  # Assumes the caller already holds the row lock (with_lock). Decrements + logs.
  # defer_review_email: when true, skip ONLY the follow_up branch (leave replenishment as-is).
  # Pass defer_review_email: true when scheduling a future visit — the member
  # hasn't arrived yet, so "how was your visit?" must not fire until they do.
  def burn_locked!(kind:, performed_by:, guest_name: nil, day_pass: nil, defer_review_email: false)
    raise NoPassesRemaining if passes_remaining.to_i <= 0 || expired?
    update!(passes_remaining: passes_remaining - 1)
    redemptions.create!(operator: operator, kind: kind.to_s, performed_by: performed_by,
                        guest_name: guest_name, day_pass: day_pass, redeemed_at: Time.current)
    enqueue_lifecycle_emails(kind, defer_review_email: defer_review_email)
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

  # Admin adds a pass back (auditable). reason is stored in guest_name to keep the table lean.
  # No-op if passes_remaining is already at quantity_purchased (prevents over-credit).
  def restore!(by:, reason: nil)
    with_lock { restore_locked!(by: by, reason: reason) }
  end

  # I1: shared restore logic — assumes the caller already holds the row lock.
  # kind controls the audit trail (e.g. "admin_restore", "schedule_cancel").
  # guest_name stores the reason/date in ISO form (no dedicated column).
  def restore_locked!(by:, reason: nil, kind: "admin_restore")
    return if passes_remaining.to_i >= quantity_purchased.to_i
    update!(passes_remaining: passes_remaining + 1)
    redemptions.create!(operator: operator, kind: kind, performed_by: by,
                        guest_name: reason, redeemed_at: Time.current)
  end
end
