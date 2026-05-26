# == Schema Information
#
# Table name: member_feedbacks
#
#  id           :bigint(8)        not null, primary key
#  anonymous    :boolean          default(FALSE), not null
#  comment      :text
#  last_read_at :datetime
#  rating       :integer
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  location_id  :integer
#  operator_id  :integer          not null
#  user_id      :integer
#
# Indexes
#
#  index_member_feedbacks_on_location_id  (location_id)
#
FactoryBot.define do
  factory :member_feedback do
    comment { "Test feedback comment" }
    rating { 5 }
    anonymous { false }
    association :operator
    association :location
    association :user

    trait :anonymous do
      anonymous { true }
    end

    trait :with_low_rating do
      rating { 2 }
    end

    trait :recent do
      created_at { 2.days.ago }
    end
  end
end
