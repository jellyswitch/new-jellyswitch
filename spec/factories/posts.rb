# == Schema Information
#
# Table name: posts
#
#  id          :bigint(8)        not null, primary key
#  title       :string           not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  location_id :integer          not null
#  user_id     :integer          not null
#
# Indexes
#
#  index_posts_on_location_id  (location_id)
#
FactoryBot.define do
  factory :post do
    title { "Sample Post Title" }
    content { "Sample post content" }
    association :user
    association :location
  end
end
