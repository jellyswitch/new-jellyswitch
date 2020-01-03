class Notifiable::Default < SimpleDelegator
  def notify
    create_feed_item
    send_notification
  end
end