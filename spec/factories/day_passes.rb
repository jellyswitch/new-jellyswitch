# == Schema Information
#
# Table name: day_passes
#
#  id               :bigint(8)        not null, primary key
#  day              :date             not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  day_pass_type_id :integer
#  invoice_id       :integer
#  operator_id      :integer          default(1), not null
#  stripe_charge_id :string
#  user_id          :integer          not null
#
# Indexes
#
#  index_day_passes_on_operator_id  (operator_id)
#

FactoryBot.define do
  factory :day_pass do
    
  end
end
