# == Schema Information
#
# Table name: offices
#
#  id             :bigint(8)        not null, primary key
#  capacity       :integer          default(1), not null
#  description    :text
#  name           :string
#  slug           :string
#  square_footage :integer          default(0), not null
#  visible        :boolean          default(TRUE), not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  location_id    :bigint(8)
#  operator_id    :bigint(8)
#
# Indexes
#
#  index_offices_on_location_id  (location_id)
#  index_offices_on_operator_id  (operator_id)
#
# Foreign Keys
#
#  fk_rails_...  (location_id => locations.id) ON DELETE => nullify
#
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
