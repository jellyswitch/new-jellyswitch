# == Schema Information
#
# Table name: plan_categories
#
#  id          :bigint(8)        not null, primary key
#  name        :string
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  location_id :integer
#  operator_id :integer
#
# Indexes
#
#  index_plan_categories_on_location_id  (location_id)
#
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
