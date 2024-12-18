FactoryBot.define do
  factory :announcement do
    association :operator
    association :user
    body { "Test Announcement" }
  end
end