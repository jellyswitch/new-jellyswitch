module FeedItemCreator
  def create_feed_item(operator, user, blob)
    feed_item = FeedItem.new
    feed_item.operator = operator
    feed_item.user = user
    feed_item.blob = blob
    
    if !feed_item.save
      context.fail!(message: "Unable to generate feed item.")
    end

    operator.users.admins.each do |admin_user|
      puts feed_item.inspect
      send_email_notification(admin_user, feed_item)
    end
  end

  def send_email_notification(user, feed_item)
    
    case feed_item.type
    when "feedback"
      FeedItemsMailer.member_feedback(user: user, feed_item: feed_item).deliver_later
    end
  end
end