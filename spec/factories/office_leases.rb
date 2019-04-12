# == Schema Information
#
# Table name: office_leases
#
#  id              :bigint(8)        not null, primary key
#  end_date        :date             not null
#  start_date      :date             not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  office_id       :bigint(8)        not null
#  operator_id     :bigint(8)        not null
#  organization_id :bigint(8)        not null
#  subscription_id :bigint(8)
#
# Indexes
#
#  index_office_leases_on_office_id        (office_id)
#  index_office_leases_on_operator_id      (operator_id)
#  index_office_leases_on_organization_id  (organization_id)
#  index_office_leases_on_subscription_id  (subscription_id)
#
# Foreign Keys
#
#  fk_rails_...  (office_id => offices.id)
#  fk_rails_...  (operator_id => operators.id)
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (subscription_id => subscriptions.id)
#

FactoryBot.define do
  factory :office_lease do
    start_date { 1.month.from_now.beginning_of_month }
    end_date { start_date + 1.year }
    operator { create(:operator_with_plans_orgs_and_offices) }

    after(:build) do |office_lease|
      operator = office_lease.operator
      office_lease.organization = operator.organizations.first
      office_lease.office = operator.offices.first
    end

    before(:create) do |office_lease|
      operator = office_lease.operator
      office_lease.organization = operator.organizations.first
      office_lease.subscription = create(
        :subscription,
        plan: operator.plans.first,
        subscribable: office_lease.organization
      )
      office_lease.office = operator.offices.first
    end
  end
end
