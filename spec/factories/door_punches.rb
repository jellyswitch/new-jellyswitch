FactoryBot.define do
  factory :door_punch do
    association :door
    association :user
    association :operator
    json { { "status" => "success" } }
  end
end