FactoryBot.define do
  factory :user_payment_profile do
    association :user
    association :location
  end
end