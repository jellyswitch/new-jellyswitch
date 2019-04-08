FactoryBot.define do
  factory :office do
    name { Faker::Movies::HarryPotter.location }
    capacity { rand(50) }
    description { Faker::Lorem.paragraph(2) }
    operator
  end
end
