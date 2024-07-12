FactoryBot.define do
  factory :user do
    name { "John Doe" }
    email { Faker::Internet.email }
    password { "password123" }
    admin { false }
    approved { true }
    archived { false }
    bill_to_organization { false }
    bio { "When you play a game of thrones you win or you die." }
    card_added { false }
    childcare_reservation_balance { 0 }
    credit_balance { 0 }
    always_allow_building_access { false }
    out_of_band { false }
    superadmin { false }
    role { "unassigned" }
    slug { "john-doe" }

    operator { Operator.find_by(name: "Cowork Tahoe") || association(:operator) }
  end
end
