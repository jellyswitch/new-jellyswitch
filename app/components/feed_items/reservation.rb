class FeedItems::Reservation < ApplicationComponent
  include ApplicationHelper

  def initialize(feed_item:)
    @feed_item = feed_item
  end

  def render?
    feed_item.reservation.present?
  end

  private

  attr_reader :feed_item

  def credits_enabled?
    feed_item.location.credits_enabled?
  end
end