FactoryBot.define do
  factory :subscription do
    trait :with_stripe_info do
      after(:create) do |subscription|
        operator = subscription.plan.operator

        subscription.stripe_subscription_id = operator.create_stripe_subscription(
          user,
          plan
        )
      end
    end
  end
end
