FactoryBot.define do
  factory :childcare_slot do
    name { "MyString" }
    week_day { 1 }
    deleted { false }
    location_id { 1 }
  end
end
