FactoryBot.define do
  factory :office do
    sequence(:name) { |n| "Office #{n}" }
    sequence(:slug) { |n| "office-#{n}" }
    capacity { 1 }
    visible { true }
    description { "" }
    square_footage { 50 }

    operator { Operator.find_by(name: "Cowork Tahoe") || association(:operator) }
    location { Location.find_by(name: "Cowork Tahoe") || association(:location) }

    trait :with_active_lease do
      after(:create) do |office|
        create(:office_lease, office: office, operator: office.operator, location: office.location, start_date: 1.month.ago, end_date: 1.month.from_now)
      end
    end
  end
end
