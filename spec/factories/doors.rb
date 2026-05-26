# == Schema Information
#
# Table name: doors
#
#  id          :bigint(8)        not null, primary key
#  available   :boolean          default(TRUE), not null
#  name        :string           not null
#  private     :boolean
#  slug        :string           not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  kisi_id     :integer
#  location_id :bigint(8)
#  operator_id :integer          default(1), not null
#
# Indexes
#
#  index_doors_on_location_id  (location_id)
#  index_doors_on_operator_id  (operator_id)
#
# Foreign Keys
#
#  fk_rails_...  (location_id => locations.id)
#
FactoryBot.define do
  factory :door do
    sequence(:name) { |n| "Door #{n}" }
    sequence(:slug) { |n| "door-#{n}" }
    available { true }
    private { false }
    sequence(:kisi_id) { |n| n }

    operator { Operator.find_by(name: "Cowork Tahoe") || association(:operator) }
    location_id { Location.find_by(name: "Cowork Tahoe").id || create(:location).id }
  end
end
