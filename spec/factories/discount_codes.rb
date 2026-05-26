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
FactoryBot.define do
  factory :discount_code do
    code { "DISCOUNT#{SecureRandom.hex(3).upcase}" }
    discount_type { "percent_off" }
    discount_value { 10 }
    applies_to { "day_pass" }
    active { true }
    operator { Operator.find_by(name: "Cowork Tahoe") || association(:operator) }
    location { operator.locations.first }
  end
end
