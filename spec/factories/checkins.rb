# == Schema Information
#
# Table name: checkins
#
#  id           :bigint(8)        not null, primary key
#  datetime_in  :datetime         not null
#  datetime_out :datetime
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  invoice_id   :integer
#  location_id  :integer          not null
#  user_id      :integer          not null
#

FactoryBot.define do
  factory :checkin do
    location_id { 1 }
    user_id { 1 }
    datetime_in { "2019-05-14 10:33:15" }
    datetime_out { "2019-05-14 10:33:15" }
  end
end
