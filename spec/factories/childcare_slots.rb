# == Schema Information
#
# Table name: childcare_slots
#
#  id          :bigint(8)        not null, primary key
#  deleted     :boolean
#  name        :string
#  week_day    :integer
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  location_id :integer
#

FactoryBot.define do
  factory :childcare_slot do
    name { "MyString" }
    week_day { 1 }
    deleted { false }
    location_id { 1 }
  end
end
