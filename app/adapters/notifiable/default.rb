class Notifiable::Default < SimpleDelegator
  # Invoked by the factory
  def notify
    log
    validate!
    create_feed_item
    send_notification if should_send_notification?
  end

  def log
    puts "Pushing message to #{recipients.count} recipients: #{message}"
  end

  def validate!
    if message.blank?
      raise "Push notification message can't be blank."
    end
  end
  
  def send_notification
    if operator.push_notification_certificate.attached?
      apn = Houston::Client.production
      apn.certificate = operator.push_notification_certificate.download

      recipients.each do |user|
        puts "Pushing message to #{user.name}: #{message}"

        if user.ios_token.present?
          notification = Houston::Notification.new(device: user.ios_token)
          notification.alert = message
    
          apn.push(notification)
          puts "Pushed message: #{message} to #{user.name}'s device: #{user.ios_token}"
        else
          puts "Cannot push message to #{user.email} since iOS token is: #{user.ios_token}"
        end

      end
    else
      puts "Operator #{operator.name} has no push notification certificate."
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