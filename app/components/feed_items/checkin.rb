class FeedItems::Checkin < ApplicationComponent
  include ApplicationHelper
  
  def initialize(feed_item:)
    @feed_item = feed_item
  end

  def render?
    feed_item.checkin.present?
  end

  private

  attr_reader :feed_item
end