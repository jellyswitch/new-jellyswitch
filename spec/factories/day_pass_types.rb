FactoryBot.define do
  factory :day_pass_type do
    name { "Day Pass" }
    operator { Operator.find_by(name: "Cowork Tahoe") || association(:operator) }
    location { Location.find_by(name: "Cowork Tahoe") }
  end
end
