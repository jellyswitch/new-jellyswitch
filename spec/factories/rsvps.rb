FactoryBot.define do
  factory :rsvp do
    association :event
    association :user
    going { true }
  end
end
