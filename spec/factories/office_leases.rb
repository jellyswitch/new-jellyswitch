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
