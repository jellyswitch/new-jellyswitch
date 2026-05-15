FactoryBot.define do
  factory :lead_note do
    association :lead
    association :user
    content { "A note about this person." }
  end
end
