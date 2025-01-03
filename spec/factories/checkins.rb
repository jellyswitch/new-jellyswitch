# spec/factories/checkins.rb
FactoryBot.define do
  factory :checkin do
    association :user
    association :location
    datetime_in { Time.current }
    datetime_out { nil }
    billable_type { 'User' }
    association :billable, factory: :user

    trait :checked_out do
      datetime_out { Time.current + 1.hour }
    end
  end
end