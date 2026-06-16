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
  def burn_locked!(kind:, performed_by:, guest_name: nil, day_pass: nil)
    raise NoPassesRemaining if passes_remaining.to_i <= 0 || expired?
    update!(passes_remaining: passes_remaining - 1)
    redemptions.create!(operator: operator, kind: kind.to_s, performed_by: performed_by,
                        guest_name: guest_name, day_pass: day_pass, redeemed_at: Time.current)
  end

  # Mirrors DayPass#subscribable — used by BillableFactory to resolve billable.
  def subscribable
    user
  end

  def charge_description
    "#{operator.name} #{day_pass_type.quantity}-Pack Day Pass Bundle"
  end

  # Admin adds a pass back (auditable). reason is stored in guest_name to keep the table lean.
  def restore!(by:, reason: nil)
    with_lock do
      update!(passes_remaining: passes_remaining + 1)
      redemptions.create!(operator: operator, kind: "admin_restore", performed_by: by,
                          guest_name: reason, redeemed_at: Time.current)
    end
  end
end
