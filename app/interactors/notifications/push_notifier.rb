# typed: true
class Notifications::PushNotifier
  include Interactor

  def call
    @message = context.message
    @operator = context.operator

    puts "Pushing message: #{@message}"
    validate!

    @apn = Houston::Client.production
    @apn.certificate = @operator.push_notification_certificate.download

    recipients.each do |user|
      push(user, @message)
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

  def push(user, message)
    if user.ios_token.present?
      notification = Houston::Notification.new(device: user.ios_token)
      notification.alert = message

      @apn.push(notification)
      puts "Pushed message: #{message} to device: #{user.ios_token}"
    else
      puts "Cannot push message to #{user.email} since iOS token is: #{user.ios_token}"
    end
  end

  def recipients
    if context.members && context.members == true
      @operator.users.all.select do |user|
        user.admin? || user.superadmin? || user.member_at_operator?(@operator)
      end
    else
      @operator.users.admins
    end
  end
end
