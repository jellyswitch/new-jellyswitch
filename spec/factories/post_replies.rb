FactoryBot.define do
  factory :post_reply do
    association :post
    association :user
  end
end