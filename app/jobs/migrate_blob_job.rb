
class MigrateBlobJob < ApplicationJob
  queue_as :default

  def perform(feed_item:)
    feed_item.update(text: feed_item.blob["text"])
    feed_item.update_columns(updated_at: feed_item.created_at)
  end
end
