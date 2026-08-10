class DayPassBundleRedemption < ApplicationRecord
  # "reservation" = a pass burned when booking a room ("use 1 pass for today",
  # ADR 0015); reservation_id links it so a cancel can restore the pass.
  # "schedule_cancel" = reverses a cancelled future-day schedule (ADR 0018),
  # restoring the pass.
  # "admin_burn" = staff spend one pass with no date attached (no DayPass row,
  # so it grants no access/coverage and can't suppress a real entry burn later
  # the same day) — e.g. an entry the door system missed. Counterpart of
  # "admin_restore"; guest_name holds the reason.
  KINDS = %w[entry guest admin_restore reservation schedule_cancel admin_burn].freeze

  belongs_to :day_pass_bundle
  belongs_to :operator
  belongs_to :performed_by, class_name: "User", optional: true
  belongs_to :day_pass, optional: true
  belongs_to :reservation, optional: true

  validates :kind, inclusion: { in: KINDS }
  validates :redeemed_at, presence: true
  # I2: prevent two entry redemptions pointing at the same DayPass (double-burn).
  # nil day_pass_id rows (guest/admin_restore/schedule_cancel) are unaffected via allow_nil.
  validates :day_pass_id, uniqueness: { scope: :kind }, allow_nil: true
end
