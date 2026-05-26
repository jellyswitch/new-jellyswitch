# == Schema Information
#
# Table name: leads
#
#  id            :bigint(8)        not null, primary key
#  source        :string
#  status        :string
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  ahoy_visit_id :integer
#  operator_id   :integer          not null
#  user_id       :integer          not null
#
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
