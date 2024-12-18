FactoryBot.define do
  factory :feed_item do
    association :operator
    association :user
    blob { { type: 'post' } }
    expense { false }
  end
end