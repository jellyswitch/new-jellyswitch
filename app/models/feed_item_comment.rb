
# == Schema Information
#
# Table name: feed_item_comments
#
#  id           :bigint(8)        not null, primary key
#  comment      :text
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  feed_item_id :integer          not null
#  user_id      :integer          not null
#

class FeedItemComment < ApplicationRecord
  belongs_to :feed_item
  belongs_to :user
  validates :comment, presence: true

  # Real-time Turbo Streams - broadcast new comments to feed item show page
  after_create_commit :broadcast_to_feed_item

  def broadcast_to_feed_item
    broadcast_append_to feed_item, target: "comments-#{feed_item_id}", partial: "operator/feed_item_comments/feed_item_comment", locals: { feed_item_comment: self }
  rescue => e
    Rails.logger.warn("FeedItemComment broadcast failed (expected in background): #{e.class}: #{e.message}")
  end

  after_commit :reindex_feed_item

  delegate :operator, :location, to: :feed_item

  def reindex_feed_item
    feed_item.reindex
  end
end
