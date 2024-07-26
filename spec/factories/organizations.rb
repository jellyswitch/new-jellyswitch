FactoryBot.define do
  factory :organization do
    association :owner, factory: :user
    association :billing_contact, factory: :user

    sequence(:name) { |n| "Organization #{n}" }
    sequence(:slug) { |n| "organization-#{n}" }
    website { "www.example.com" }
    out_of_band { true }
    stripe_customer_id { nil }

    operator { Operator.find_by(name: "Cowork Tahoe") || association(:operator) }
  end
end
