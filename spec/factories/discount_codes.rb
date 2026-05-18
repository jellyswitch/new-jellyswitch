FactoryBot.define do
  factory :discount_code do
    code { "DISCOUNT#{SecureRandom.hex(3).upcase}" }
    discount_type { "percent_off" }
    discount_value { 10 }
    applies_to { "day_pass" }
    active { true }
    operator { Operator.find_by(name: "Cowork Tahoe") || association(:operator) }
    location { operator.locations.first }
  end
end
