class DayPassBundleRedemption < ApplicationRecord
  KINDS = %w[entry guest admin_restore schedule_cancel].freeze

  belongs_to :day_pass_bundle
  belongs_to :operator
  belongs_to :performed_by, class_name: "User", optional: true
  belongs_to :day_pass, optional: true

  validates :kind, inclusion: { in: KINDS }
  validates :redeemed_at, presence: true
  # I2: prevent two entry redemptions pointing at the same DayPass (double-burn).
  # nil day_pass_id rows (guest/admin_restore/schedule_cancel) are unaffected via allow_nil.
  validates :day_pass_id, uniqueness: { scope: :kind }, allow_nil: true
end
