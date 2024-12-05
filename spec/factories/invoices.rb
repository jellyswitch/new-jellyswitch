FactoryBot.define do
  factory :invoice do
    association :operator
    association :billable, factory: :organization
    association :location
    amount_due { 1000 }
    amount_paid { 0 }
    date { Time.current }
    due_date { 30.days.from_now }
    status { 'open' }
    number { "INV-#{SecureRandom.hex(4)}" }
  end
end