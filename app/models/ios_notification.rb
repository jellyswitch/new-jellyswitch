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
    # Without an explicit sound, APNs delivers the push silently regardless
    # of what the client's notification handler requests. "default" plays the
    # system default tone — audible push, no custom asset required.
    notification.sound = "default"
    notification.topic = user.operator.bundle_id
    notification.custom_payload = custom_payload if custom_payload.present?
    response = connection.push(notification)
    connection.close

    if response && !response.ok?
      Rails.logger.error "[APNs] Push failed for #{user.operator.bundle_id}: status=#{response.status} body=#{response.body}"
    elsif response
      Rails.logger.info "[APNs] Push sent for #{user.operator.bundle_id}: status=#{response.status}"
    else
      Rails.logger.error "[APNs] Push returned nil response for #{user.operator.bundle_id}"
    end

    response
  end

  # expo-notifications only exposes a REMOTE push's data to JS when it arrives
  # under a "body" key in the APNs userInfo — EXNotificationSerializer maps
  # content.data = userInfo["body"] for remote notifications, and top-level
  # custom keys are invisible to the tap handler. That's why notification deep
  # links never routed on real iPhones even though the JS routing was correct
  # (local-notification tests put data straight into content.data, so they
  # passed). Do NOT flatten this back.
  def custom_payload
    return nil if data.blank?
    { "body" => data }
  end

  def validate!
    raise "No Bundle ID" if user.operator.bundle_id.blank?
    raise "No iOS token" if user.ios_token.blank?
    raise "APNs key not configured" if ENV["APNS_KEY_FILE"].blank?
    raise "APNs key ID not configured" if ENV["APNS_KEY_ID"].blank?
    raise "APNs team ID not configured" if ENV["APNS_TEAM_ID"].blank?
  end
end