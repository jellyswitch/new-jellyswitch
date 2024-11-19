FactoryBot.define do
  factory :day_pass do
    day { Date.today }
    operator { Operator.find_by(name: "Cowork Tahoe") || association(:operator) }
    location { Location.find_by(name: "Cowork Tahoe") }
    user { association(:user) }
    day_pass_type { association(:day_pass_type) }
    billable { association(:user) }
  end
end
