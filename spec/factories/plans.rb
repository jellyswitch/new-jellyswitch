# == Schema Information
#
# Table name: plans
#
#  id                            :bigint(8)        not null, primary key
#  always_allow_building_access  :boolean          default(TRUE), not null
#  amount_in_cents               :integer          not null
#  available                     :boolean          default(TRUE), not null
#  childcare_reservations        :integer          default(0), not null
#  commitment_interval           :integer
#  credits                       :integer          default(0), not null
#  day_limit                     :integer          default(0), not null
#  has_day_limit                 :boolean          default(FALSE), not null
#  included_meeting_room_minutes :integer
#  interval                      :string           not null
#  name                          :string           not null
#  overage_rate_in_cents         :integer          default(0)
#  plan_type                     :string
#  slug                          :string
#  visible                       :boolean          default(TRUE), not null
#  created_at                    :datetime         not null
#  updated_at                    :datetime         not null
#  location_id                   :integer
#  operator_id                   :integer          default(1), not null
#  plan_category_id              :integer
#  stripe_plan_id                :string
#
# Indexes
#
#  index_plans_on_location_id  (location_id)
#  index_plans_on_operator_id  (operator_id)
#
FactoryBot.define do
  factory :plan do
    interval { "monthly" }
    amount_in_cents { 20500 }
    sequence(:name) { |n| "Plan #{n}" }
    visible { true }
    available { true }
    sequence(:slug) { |n| "plan-#{n}-#{SecureRandom.uuid}" }
    sequence(:stripe_plan_id) { |n| "stripe-plan-#{n}-#{SecureRandom.uuid}" }
    plan_type { "individual" }
    always_allow_building_access { true }
    has_day_limit { false }
    day_limit { 0 }
    credits { 0 }
    commitment_interval { nil }
    childcare_reservations { 0 }

    operator { Operator.find_by(name: "Cowork Tahoe") || association(:operator) }

    after(:create) do |plan|
      plan.location ||= (Location.find_by(name: "Cowork Tahoe") || create(:location))
      plan.save!
    end
  end
end
