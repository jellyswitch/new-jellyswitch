# == Schema Information
#
# Table name: events
#
#  id                :bigint(8)        not null, primary key
#  approved_at       :datetime
#  description       :text
#  ends_at           :datetime
#  location_string   :string
#  rejected_at       :datetime
#  starts_at         :datetime         not null
#  submitted_via_app :boolean          default(FALSE), not null
#  title             :string           not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  location_id       :integer          not null
#  user_id           :integer          not null
#
# Indexes
#
#  index_events_on_approved_at  (approved_at)
#
FactoryBot.define do
  factory :event do
    sequence(:title) { |n| "Event #{n}" }
    association :location
    association :user
    starts_at { Time.current }
  end
end
