class IosNotification
  attr_reader :user, :message, :data

  def initialize(user:, message:, data: {})
    @user = user
    @message = message
    @data = data
  end

  def send!
    validate!
    connection = Apnotic::Connection.new(cert_path: StringIO.new(user.operator.push_notification_certificate.download), cert_pass: "pass")
    notification = Apnotic::Notification.new(user.ios_token)
    notification.alert = message
    notification.topic = user.operator.bundle_id
    notification.custom_payload = data if data.present?
    response = connection.push(notification)
    connection.close
    response
  end

  def validate!
    raise "No Bundle ID" if user.operator.bundle_id.blank?
    raise "No iOS token" if user.ios_token.blank?
  end
end