FactoryBot.define do
  factory :member_feedback do
    comment { "Test feedback comment" }
    rating { 5 }
    anonymous { false }
    association :operator
    association :location
    association :user

    trait :anonymous do
      anonymous { true }
    end

    trait :with_low_rating do
      rating { 2 }
    end

    trait :recent do
      created_at { 2.days.ago }
    end
  end
end