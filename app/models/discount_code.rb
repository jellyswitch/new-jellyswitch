# == Schema Information
#
# Table name: discount_codes
#
#  id               :bigint(8)        not null, primary key
#  active           :boolean          default(TRUE), not null
#  applies_to       :string           default("all"), not null
#  code             :string           not null
#  discount_type    :string           not null
#  discount_value   :integer          not null
#  expires_at       :datetime
#  max_redemptions  :integer
#  redemption_count :integer          default(0), not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  location_id      :integer
#  operator_id      :integer          not null
#  stripe_coupon_id :string
#
# Indexes
#
#  index_discount_codes_on_operator_id_and_code         (operator_id,code) UNIQUE
#  index_discount_codes_on_operator_id_and_location_id  (operator_id,location_id)
#
class DiscountCode < ApplicationRecord
  include HasLocation

  belongs_to :operator
  acts_as_tenant :operator

  has_many :discount_redemptions, dependent: :restrict_with_error

  validates :code, presence: true
  validates :code, uniqueness: { scope: :operator_id, case_sensitive: false }
  validates :discount_type, presence: true, inclusion: { in: %w[percent_off amount_off] }
  validates :discount_value, presence: true, numericality: { greater_than: 0 }
  validates :applies_to, presence: true, inclusion: { in: %w[day_pass membership meeting_room all] }
  validate :percent_off_max_100

  scope :active, -> { where(active: true) }
  scope :not_expired, -> { where("expires_at IS NULL OR expires_at > ?", Time.current) }
  scope :available, -> { active.not_expired }
  scope :for_product, ->(product) { where(applies_to: [product, "all"]) }
  scope :for_code, ->(code) { where("LOWER(code) = ?", code.to_s.downcase.strip) }

  def redeemable?
    active? && !expired? && !max_redemptions_reached?
  end

  def expired?
    expires_at.present? && expires_at <= Time.current
  end

  def max_redemptions_reached?
    max_redemptions.present? && redemption_count >= max_redemptions
  end

  def calculate_discount(original_amount_in_cents)
    if discount_type == "percent_off"
      (original_amount_in_cents * discount_value / 100.0).round
    else
      [discount_value, original_amount_in_cents].min
    end
  end

  def discount_display
    if discount_type == "percent_off"
      "#{discount_value}% off"
    else
      "$#{'%.2f' % (discount_value / 100.0)} off"
    end
  end

  def applies_to_display
    case applies_to
    when "day_pass" then "Day Passes"
    when "membership" then "Memberships"
    when "meeting_room" then "Meeting Rooms"
    when "all" then "All Products"
    end
  end

  private

  def percent_off_max_100
    if discount_type == "percent_off" && discount_value.present? && discount_value > 100
      errors.add(:discount_value, "can't exceed 100 for percentage discounts")
    end
  end
end
