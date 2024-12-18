FactoryBot.define do
  factory :event do
    sequence(:title) { |n| "Event #{n}" }
    association :location
    association :user
    starts_at { Time.current }
  end
end