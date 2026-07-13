# == Schema Information
#
# Table name: day_pass_types
#
#  id                            :bigint(8)        not null, primary key
#  always_allow_building_access  :boolean          default(FALSE), not null
#  amount_in_cents               :integer          default(0), not null
#  available                     :boolean          default(TRUE), not null
#  code                          :string
#  default_for_room_booking      :boolean          default(FALSE), not null
#  included_meeting_room_minutes :integer
#  name                          :string           not null
#  overage_rate_in_cents         :integer          default(0), not null
#  visible                       :boolean          default(TRUE), not null
#  created_at                    :datetime         not null
#  updated_at                    :datetime         not null
#  location_id                   :integer
#  operator_id                   :integer          not null
#
# Indexes
#
#  index_day_pass_types_on_location_id  (location_id)
#  index_dpt_on_op_loc_default          (operator_id,location_id,default_for_room_booking)
#

class DayPassType < ApplicationRecord
  include HasLocation

  has_many :day_passes
  belongs_to :operator
  acts_as_tenant :operator

  has_rich_text :description

  # Scopes
  scope :available, -> { where(available: true) }
  scope :unavailable, -> { where(available: false) }
  scope :visible, -> { where(visible: true) }
  scope :invisible, -> { where(visible: false) }
  scope :free, -> { where(amount_in_cents: 0) }
  scope :for_operator, ->(operator) { where(operator_id: operator.id) }
  # Case-insensitive + whitespace-tolerant lookup. Matches DiscountCode#for_code.
  # Shelley reported a real-world failure where her discount code didn't work
  # because exact-match case-sensitive comparison rejected anything other than
  # the stored capitalization.
  scope :for_code, ->(code) { where("LOWER(code) = ?", code.to_s.downcase.strip) }
  scope :cheapest, -> { order("amount_in_cents ASC").first }

  def self.options_for_select(operator)
    where(operator_id: operator.id).available.visible
  end

  def self.all_options_for_select(location, user)
    if user.has_billing_for_location?(location) || user.out_of_band?
      where(location_id: location.id).available
    else
      where(location_id: location.id).available.free
    end
  end

  validates :quantity, numericality: { only_integer: true, greater_than_or_equal_to: 1 }
  validates :daily_limit, numericality: { only_integer: true, greater_than_or_equal_to: 1 },
                          allow_nil: true

  # Presented wherever expiration can be enabled. NOT legal advice.
  EXPIRATION_DISCLAIMER =
    "Expiration on prepaid passes is restricted or prohibited in many states, " \
    "including California (Civil Code §1749.5). It can't be enabled for this location.".freeze

  validate :expiration_allowed_for_location

  def expiration_allowed_for_location
    return if expires_after_days.blank?
    if location.nil? || location.expiration_restricted?
      errors.add(:expires_after_days, EXPIRATION_DISCLAIMER)
    end
  end

  # A quantity > 1 product is an N-Pack (a Day Pass Bundle); quantity 1 is a
  # single day pass. See CONTEXT.md → Day Pass Bundle.
  def bundle?
    quantity.to_i > 1
  end

  # Daily sales cap. Every DayPass row of this type on that day at that
  # location counts — purchased, comped, or bundle-sourced — because the limit
  # models physical capacity (e.g. the building has 2 day offices), not sales
  # volume. Enforced only at member self-serve entry points; staff/admin and
  # door-entry paths never call this (their rows still count).
  def daily_limit_reached?(day:, location:)
    return false if daily_limit.nil?
    day_passes.where(location: location, day: day).count >= daily_limit
  end

  def free?
    amount_in_cents == 0
  end

  # Meeting room limit helpers
  def has_meeting_room_limit?
    included_meeting_room_minutes.present?
  end

  def overage_rate_per_minute_in_cents
    overage_rate_in_cents / 60.0
  end
end
