# == Schema Information
#
# Table name: rsvps
#
#  id            :bigint(8)        not null, primary key
#  going         :boolean          default(TRUE), not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  ahoy_visit_id :bigint(8)
#  event_id      :integer          not null
#  user_id       :integer          not null
#
FactoryBot.define do
  factory :rsvp do
    association :event
    association :user
    going { true }
  end
end
