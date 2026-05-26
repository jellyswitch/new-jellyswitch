# == Schema Information
#
# Table name: checkins
#
#  id            :bigint(8)        not null, primary key
#  billable_type :string
#  datetime_in   :timestamptz      not null
#  datetime_out  :timestamptz
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  billable_id   :bigint(8)
#  invoice_id    :integer
#  location_id   :integer          not null
#  user_id       :integer          not null
#
# Indexes
#
#  index_checkins_on_billable_type_and_billable_id  (billable_type,billable_id)
#  index_checkins_on_location_id                    (location_id)
#
# spec/factories/checkins.rb
FactoryBot.define do
  factory :checkin do
    association :user
    association :location
    datetime_in { Time.current }
    datetime_out { nil }
    billable_type { 'User' }
    association :billable, factory: :user

    trait :checked_out do
      datetime_out { Time.current + 1.hour }
    end
  end
end
