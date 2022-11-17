class Notifiable::Default < SimpleDelegator
  # Invoked by the factory
  def notify
    validate!
    create_feed_item
    send_notification if should_send_notification?
  end

  def validate!
    if message.blank?
      raise "Push notification message can't be blank."
    end
    
    recipients # will raise an error if not defined
  end
  
  def send_notification
    ios
    android
  end

  def ios
    if operator.push_notification_certificate.attached?
      recipients.each do |user|
        begin
          if user.ios_token.present?
            IosNotification.new(user: user, message: message).send!
          end
        rescue => e
          Honeybadger.notify(e, user_id: user.email, operator_id: operator.id, notification: message)
        end
      end
    end
  end

  def android
    if operator.android_server_key.present?
      recipients.each do |user|
        if user.android_token.present?
          fcm = FCM.new(operator.android_server_key)
          fcm.send([user.android_token], {"notification": {"title": message, "body": message}})
        end
      end
    end
  end
  
  def message
    raise "Implement in a subclass"
  end
  
  def recipients
    raise "Implement in subclass"
  end
  
  def should_send_notification?
    raise "Implement in a subclass"
  end
  
  def recipients
    raise "Implement in a subclass"
  end
  
  def create_feed_item
    raise "Implement in a subclass"
  end
end
