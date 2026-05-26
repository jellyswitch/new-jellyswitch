# == Schema Information
#
# Table name: post_replies
#
#  id         :bigint(8)        not null, primary key
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  post_id    :integer          not null
#  user_id    :integer          not null
#
FactoryBot.define do
  factory :post_reply do
    association :post
    association :user
  end
end
