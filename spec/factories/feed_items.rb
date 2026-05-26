# == Schema Information
#
# Table name: feed_items
#
#  id          :bigint(8)        not null, primary key
#  blob        :jsonb            not null
#  expense     :boolean          default(FALSE), not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  location_id :integer
#  operator_id :integer          not null
#  user_id     :integer
#
# Indexes
#
#  index_feed_items_on_blob         (blob) USING gin
#  index_feed_items_on_location_id  (location_id)
#
FactoryBot.define do
  factory :feed_item do
    association :operator
    association :user
    blob { { type: 'post' } }
    expense { false }
  end
end
