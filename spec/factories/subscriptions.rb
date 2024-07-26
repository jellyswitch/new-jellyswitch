FactoryBot.define do
  factory :subscription do
    association :plan
    active { true }
    stripe_subscription_id { nil }
    pending { false }
    start_date { Time.current.to_date }
    paused { false }
    cancelling_at_end_of_billing_period { false }

    association :subscribable, factory: :user
    association :billable, factory: :user
    subscribable_type { "User" }
    billable_type { "User" }

    trait :for_organization do
      association :subscribable, factory: :organization
      association :billable, factory: :organization
      subscribable_type { "Organization" }
      billable_type { "Organization" }
    end
  end
end
