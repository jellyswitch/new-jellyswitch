class FeedItemComponent < ApplicationComponent
  include LayoutHelper

  def initialize(feed_item:, comments:)
    @feed_item = feed_item
    @comments = comments
  end

  private

  attr_reader :feed_item, :comments

  def show_feed_item?
    if feed_item.type == "reservation"
      if feed_item.operator.reservation_notifications?
        true
      else
        false
      end
    else
      if feed_item.type == "new-user"
        false
      else
        true
      end
    end
  end

  def subcomponent
    case feed_item.type
    when "reservation"
      FeedItems::Reservation
    else
      "operator/feed_items/#{feed_item.type.underscore}_feed_item"
    end
  end
end