FactoryBot.define do
  factory :office_lease do
    association :organization
    association :office
    association :subscription

    start_date { 6.months.ago.to_date }
    end_date { 6.months.from_now.to_date }

    initial_invoice_date { 6.months.ago.to_date }
    always_allow_building_access { true }

    operator { Operator.find_by(name: "Cowork Tahoe") || association(:operator) }
    location { Location.find_by(name: "Cowork Tahoe") || association(:location) }
  end
end
