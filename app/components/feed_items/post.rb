class FeedItems::Post < ApplicationComponent
  include ApplicationHelper

  def initialize(feed_item:)
    @feed_item = feed_item
    @rich_text = ActionText::RichText.where(record_id: feed_item.id)
  end

  private

  attr_reader :feed_item
end