class IosNotification
  attr_reader :user, :message

  def initialize(user:, message:)
    @user = user
    @message = message
  end

  def send!
    validate!
    connection = Apnotic::Connection.new(cert_path: StringIO.new(user.operator.push_notification_certificate.download), cert_pass: "pass")
    notification = Apnotic::Notification.new(user.ios_token)
    notification.alert = message
    notification.topic = user.operator.bundle_id
    response = connection.push(notification)
    connection.close
    response
  end

  def validate!
    raise "No Bundle ID" if user.operator.bundle_id.blank?
    raise "No iOS token" if user.ios_token.blank?
  end
end