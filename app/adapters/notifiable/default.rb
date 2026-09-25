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
    
    recipients # will raise an error if not defined
  end
  
  def send_notification
    ios
    android
  end

  def deep_link_data
    {}
  end

  def ios
    if apns_configured? && operator.bundle_id.present?
      recipients.each do |user|
        puts "Pushing iOS notification to #{user.name}: #{message}"

        begin
          if user.ios_token.present?
            response = IosNotification.new(user: user, message: message, data: deep_link_data).send!
            if response.ok?
              puts "Pushed iOS message: #{message} to #{user.name}'s device: #{user.ios_token}"
            else
              puts "Cannot push iOS message: #{ response.body }"
            end
          else
            puts "Cannot push iOS message to #{user.email} since iOS token is: #{user.ios_token}"
          end
        rescue => e
          Honeybadger.notify(e, user_id: user.email, operator_id: operator.id, notification: message)
        end
      end
    else
      puts "Operator #{operator.name} has no APNs configuration or bundle_id is missing"
      alert_missing_push_config(:ios)
    end
  end

  def apns_configured?
    ENV["APNS_KEY_FILE"].present? && ENV["APNS_KEY_ID"].present? && ENV["APNS_TEAM_ID"].present?
  end

  def android
    if operator.android_push_notification_key.attached? && operator.firebase_project_id.present?
      recipients.each do |user|
        puts "Pushing android notification to #{user.name}: #{message}"
        if user.android_token.present?
          fcm = FCM.new('',StringIO.new(operator.android_push_notification_key.download),operator.firebase_project_id)
          fcm.send_v1(android_payload(user))
          puts "Pushed message: #{message} to #{user.name}'s android device: #{user.android_token}"
        else
          puts "Cannot push Android message to #{user.email} since android token is: #{user.android_token}"
        end
      end
    else
      puts "Operator #{operator.name} has no firebase server key."
      alert_missing_push_config(:android)
    end
  end

  # A skipped send is a silent failure when real devices are registered —
  # that's how a brand can launch with tokens piling up and zero pushes ever
  # delivered. Alert Honeybadger, but at most once per operator/platform/day.
  def alert_missing_push_config(platform)
    token_column = platform == :ios ? :ios_token : :android_token
    registered = operator.users.where.not(token_column => [nil, ""]).count
    return if registered.zero?

    cache_key = "notifiable/missing_push_config_alert/#{operator.id}/#{platform}"
    return unless Rails.cache.write(cache_key, true, expires_in: 1.day, unless_exist: true)

    Honeybadger.notify(
      "Operator #{operator.name} (##{operator.id}) has #{registered} user(s) with registered #{platform} push tokens but #{platform} push is not configured — notifications are being silently skipped.",
      error_class: "Notifiable::MissingPushConfig",
      fingerprint: "missing_push_config/#{operator.id}/#{platform}",
      context: {
        operator_id: operator.id,
        operator_name: operator.name,
        platform: platform,
        registered_token_count: registered,
        apns_env_configured: apns_configured?,
        bundle_id_present: operator.bundle_id.present?,
        firebase_project_id_present: operator.firebase_project_id.present?,
        firebase_key_attached: operator.android_push_notification_key.attached?
      }
    )
  end
  
  def android_payload(user)
    payload = {
      "token": user.android_token,
      "notification": {
        "title": message,
        "body": message
      },
      # Pin to the channel the mobile app creates with HIGH importance
      # and request the default tone explicitly. Without this, FCM
      # routes to the implicit "Miscellaneous" channel on some
      # Android versions, which is silent by default.
      "android": {
        "notification": {
          "sound": "default",
          "channel_id": "default",
        }
      }
    }
    # expo-notifications on Android reads a remote push's data from a JSON
    # string under the FCM data map's "body" key (NotificationData#body) —
    # flat top-level data keys never reach the JS tap handler, which is why
    # notification deep links didn't route on real devices. Do NOT flatten
    # this back to individual keys.
    payload["data"] = { "body" => deep_link_data.to_json } if deep_link_data.present?
    payload
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
