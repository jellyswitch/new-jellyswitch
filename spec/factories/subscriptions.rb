# == Schema Information
#
# Table name: subscriptions
#
#  id                                  :bigint(8)        not null, primary key
#  active                              :boolean          default(TRUE), not null
#  billable_type                       :string
#  cancelling_at_end_of_billing_period :boolean          default(FALSE), not null
#  paused                              :boolean          default(FALSE), not null
#  pending                             :boolean          default(FALSE), not null
#  start_date                          :date             not null
#  subscribable_type                   :string
#  created_at                          :datetime         not null
#  updated_at                          :datetime         not null
#  billable_id                         :bigint(8)
#  plan_id                             :integer          not null
#  stripe_subscription_id              :string
#  subscribable_id                     :bigint(8)
#
# Indexes
#
#  index_subscriptions_on_billable_type_and_billable_id          (billable_type,billable_id)
#  index_subscriptions_on_subscribable_type_and_subscribable_id  (subscribable_type,subscribable_id)
#
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
