# == Schema Information
#
# Table name: door_punches
#
#  id          :bigint(8)        not null, primary key
#  json        :jsonb
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  door_id     :integer
#  operator_id :integer          default(1), not null
#  user_id     :integer
#
# Indexes
#
#  index_door_punches_on_operator_id  (operator_id)
#
FactoryBot.define do
  factory :door_punch do
    association :door
    association :user
    association :operator
    json { { "status" => "success" } }
  end
end
