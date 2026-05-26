# == Schema Information
#
# Table name: announcements
#
#  id          :bigint(8)        not null, primary key
#  body        :text
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  location_id :integer
#  operator_id :integer
#  user_id     :integer
#
# Indexes
#
#  index_announcements_on_location_id  (location_id)
#
FactoryBot.define do
  factory :announcement do
    association :operator
    association :user
    body { "Test Announcement" }
  end
end
