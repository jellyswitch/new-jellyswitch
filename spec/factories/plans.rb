FactoryBot.define do
  factory :plan do
    name { 'Full Time Membership '}
    interval { 'monthly' }
    amount_in_cents { 40_000 }
    visible { true }
    available { true }
  end
end
