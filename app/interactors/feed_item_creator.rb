module FeedItemCreator
  def create_feed_item(operator, user, blob)
    feed_item = FeedItem.new
    feed_item.operator = operator
    feed_item.user = user
    feed_item.blob = blob
    
    if !feed_item.save
      context.fail!(message: "Unable to generate feed item.")
    end
  end
end