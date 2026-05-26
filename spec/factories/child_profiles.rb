# == Schema Information
#
# Table name: child_profiles
#
#  id         :bigint(8)        not null, primary key
#  birthday   :datetime
#  name       :string
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  user_id    :integer
#
FactoryBot.define do
  factory :child_profile do
    sequence(:name) { |n| "Child #{n}" }
    birthday { Date.current - 5.years }
    notes { "Test notes" }
    association :user

    trait :with_photo do
      after(:build) do |profile|
        profile.photo.attach(
          io: File.open(Rails.root.join('spec', 'fixtures', 'test.jpg')),
          filename: 'test.jpg',
          content_type: 'image/jpeg'
        )
      end
    end
  end
end
