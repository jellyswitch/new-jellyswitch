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
