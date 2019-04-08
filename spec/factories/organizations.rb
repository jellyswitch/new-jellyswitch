FactoryBot.define do
  factory :organization do
    operator
    owner
    name { Faker::Company.name }
    website { "https://www.example.com" }
  end
end
