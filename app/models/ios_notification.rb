class IosNotification
  attr_reader :user, :message, :data

  def initialize(user:, message:, data: {})
    @user = user
    @message = message
    @data = data
  end

  def send!
    validate!
    connection = Apnotic::Connection.new(
      auth_method: :token,
      cert_path: StringIO.new(ENV.fetch("APNS_KEY_FILE")),
      key_id: ENV.fetch("APNS_KEY_ID"),
      team_id: ENV.fetch("APNS_TEAM_ID")
    )
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
    raise "APNs key not configured" if ENV["APNS_KEY_FILE"].blank?
    raise "APNs key ID not configured" if ENV["APNS_KEY_ID"].blank?
    raise "APNs team ID not configured" if ENV["APNS_TEAM_ID"].blank?
  end
end