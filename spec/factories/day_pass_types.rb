FactoryBot.define do
  factory :day_pass_type do
    sequence(:name) { |n| "Jellywork day pass #{n}" }
    amount_in_cents { rand(8_000) }
    operator
  end
end
