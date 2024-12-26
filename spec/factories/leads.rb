FactoryBot.define do
  factory :lead do
    association :user
    association :operator
    association :ahoy_visit, factory: :ahoy_visit
    source { Lead::SOURCES[:web] }
    status { Lead::STATUSES[:open] }
  end

  factory :ahoy_visit, class: 'Ahoy::Visit' do

  end
end