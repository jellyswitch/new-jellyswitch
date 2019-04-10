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
#  plan_id         :bigint(8)        not null
#
# Indexes
#
#  index_office_leases_on_office_id        (office_id)
#  index_office_leases_on_operator_id      (operator_id)
#  index_office_leases_on_organization_id  (organization_id)
#  index_office_leases_on_plan_id          (plan_id)
#
# Foreign Keys
#
#  fk_rails_...  (office_id => offices.id)
#  fk_rails_...  (operator_id => operators.id)
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (plan_id => plans.id)
#

FactoryBot.define do
  factory :office_lease do
    start_date { 1.month.from_now.beginning_of_month }
    end_date { start_date + 1.year }
    operator

    after(:build) do |office_lease|
      operator = office_lease.operator
      plan = create(:plan, operator: operator, plan_type: 'lease')
      office_lease.plan = plan
      organization = build(:organization, operator: operator)
      organization.operator = operator
      organization.save!
      office_lease.organization = organization
      office = create(:office, operator: operator)
      office_lease.office = office
    end
  end
end
