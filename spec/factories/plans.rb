# == Schema Information
#
# Table name: plans
#
#  id              :bigint(8)        not null, primary key
#  amount_in_cents :integer          not null
#  available       :boolean          default(TRUE), not null
#  interval        :string           not null
#  name            :string           not null
#  plan_type       :string
#  slug            :string
#  visible         :boolean          default(TRUE), not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  operator_id     :integer          default(1), not null
#  stripe_plan_id  :string
#
# Indexes
#
#  index_plans_on_operator_id  (operator_id)
#

FactoryBot.define do
  factory :plan do
    sequence(:name) { |n| "Membership #{n}" }
    interval { 'monthly' }
    amount_in_cents { 40_000 }
    visible { true }
    available { true }
    plan_type { 'individual' }
    operator { create(:operator) }
  end
end
