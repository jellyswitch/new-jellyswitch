class Notifiable::Default < SimpleDelegator
  def notify
    create_feed_item
    send_notification if should_send_notification?
  end
end