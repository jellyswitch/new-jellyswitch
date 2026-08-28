class ShowcaseCard < ApplicationRecord
  SLOTS = %w[day_passes memberships standalone].freeze

  belongs_to :operator
  belongs_to :location

  acts_as_tenant :operator

  validates :label, :url, presence: true
  validates :slot, inclusion: { in: SLOTS }
  # Outbound links leave the operator's site — only web URLs make sense, and a
  # javascript: URL pasted into the form must never reach visitors' pages.
  validates :url, format: { with: %r{\Ahttps?://}i, message: "must start with http:// or https://" }

  scope :for_slot, ->(slot) { where(slot: slot, visible: true).order(:display_order, :id) }
end
