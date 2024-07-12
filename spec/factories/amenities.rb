FactoryBot.define do
  factory :amenity do
    sequence(:name) { |n| "Amenity #{n}" }
    price { Faker::Number.between(from: 10.0, to: 25.0) }
    membership_price { Faker::Number.between(from: 0, to: 10.0) }

    association :room
  end
end
