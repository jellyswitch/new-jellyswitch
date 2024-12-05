FactoryBot.define do
  factory :plan_category do
    sequence(:name) { |n| "Plan Category #{n}" }
    association :operator
    association :location

    trait :with_plans do
      after(:create) do |category|
        create_list(:plan, 3, plan_category: category)
      end
    end

    factory :plan_category_with_plans do
      with_plans
    end
  end
end