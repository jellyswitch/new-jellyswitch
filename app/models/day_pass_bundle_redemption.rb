class DayPassBundleRedemption < ApplicationRecord
  # "reservation" = a pass burned when booking a room ("use 1 pass for today",
  # ADR 0015); reservation_id links it so a cancel can restore the pass.
  KINDS = %w[entry guest admin_restore reservation].freeze

  belongs_to :day_pass_bundle
  belongs_to :operator
  belongs_to :performed_by, class_name: "User", optional: true
  belongs_to :day_pass, optional: true
  belongs_to :reservation, optional: true

  validates :kind, inclusion: { in: KINDS }
  validates :redeemed_at, presence: true
end
