class Notifications::PushNotifier
  include Interactor

  def call
    @message = context.message
    @operator = context.operator

    puts "Pushing message: #{@message}"
    validate!

    apn = Houston::Client.production # change this
    apn.certificate = @operator.push_notification_certificate.download

    @operator.users.admins.each do |user|
      if user.ios_token.present?
        notification = Houston::Notification.new(device: user.ios_token)
        notification.alert = @message

        apn.push(notification)
        puts "Pushed message: #{@message} to device: #{user.ios_token}"
      end
    end
  end

  def validate!
    if @message.blank?
      context.fail!(message: "Message can't be blank.")
    end

    if !@operator.push_notification_certificate.attached?
      context.fail!(message: "Operator #{@operator.name} has no push notification certificate.")
    end
  end
end
