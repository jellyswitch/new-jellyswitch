# Receives Sendgrid Event Webhook POSTs and routes them into the activity
# timeline + User email-status flags.
#
# Configure in Sendgrid: Settings → Mail Settings → Event Webhook.
# Webhook URL: https://<your-host>/sendgrid/events
#
# Signed-payload verification (recommended for prod):
#   1. In Sendgrid → Mail Settings → Event Webhook → Signature Verification, enable it
#      and copy the base64-encoded public verification key.
#   2. Set `SENDGRID_WEBHOOK_VERIFICATION_KEY` to that key. The controller
#      then rejects (401) any request whose Ed25519 signature doesn't match.
#   3. With the key unset (dev/test), requests are accepted without verification.
class Sendgrid::EventsController < ApplicationController
  skip_before_action :verify_authenticity_token, raise: false
  skip_forgery_protection

  SIGNATURE_HEADER = "HTTP_X_TWILIO_EMAIL_EVENT_WEBHOOK_SIGNATURE".freeze
  TIMESTAMP_HEADER = "HTTP_X_TWILIO_EMAIL_EVENT_WEBHOOK_TIMESTAMP".freeze
  SIGNATURE_MAX_AGE = 10.minutes # reject replays of old captures

  ENGAGEMENT_KINDS = {
    "open" => "email_opened",
    "click" => "email_clicked",
  }.freeze

  def receive
    raw_body = request.body.read
    return head :unauthorized unless authenticated?(raw_body)
    events = parse_events(raw_body)
    return head :bad_request if events.nil?
    events.each { |event| handle_event(event) }
    head :ok
  end

  private

  # Verifies the Ed25519 signature on the raw POST body per Sendgrid spec:
  #   payload-to-sign = timestamp + raw_body
  #   signature       = base64(Ed25519.sign(private_key, payload-to-sign))
  # Returns true if verification passes OR if no verification key is configured
  # (allows dev/test to POST without setup).
  def authenticated?(raw_body)
    expected_key = ENV["SENDGRID_WEBHOOK_VERIFICATION_KEY"]
    return true if expected_key.blank?

    signature_b64 = request.env[SIGNATURE_HEADER]
    timestamp = request.env[TIMESTAMP_HEADER]
    return false if signature_b64.blank? || timestamp.blank?

    # Replay-protection: reject timestamps older than SIGNATURE_MAX_AGE.
    return false if (Time.current.to_i - timestamp.to_i).abs > SIGNATURE_MAX_AGE.to_i

    verify_key = Ed25519::VerifyKey.new(Base64.decode64(expected_key))
    verify_key.verify(Base64.decode64(signature_b64), timestamp + raw_body)
    true
  rescue Ed25519::VerifyError, ArgumentError
    false
  end

  def parse_events(raw_body)
    return [] if raw_body.blank?
    parsed = JSON.parse(raw_body)
    parsed.is_a?(Array) ? parsed : nil
  rescue JSON::ParserError
    nil
  end

  def handle_event(event)
    email = event["email"]&.downcase
    return if email.blank?

    users = User.where("lower(email) = ?", email)
    return if users.empty?

    case event["event"]
    when "open", "click"
      kind = ENGAGEMENT_KINDS[event["event"]]
      users.each do |user|
        record_engagement_activity(user, kind, event)
        update_campaign_send_engagement(user, event["event"])
      end
    when "bounce", "dropped"
      users.find_each { |u| u.update_columns(email_bounced: true) }
    when "spamreport"
      users.find_each { |u| u.update_columns(email_opted_out: true) }
    end
  rescue => e
    Rails.logger.warn("Sendgrid event error: #{e.class}: #{e.message}")
    Honeybadger.notify(e) if defined?(Honeybadger)
  end

  def record_engagement_activity(user, kind, event)
    Activity.log(
      user: user,
      operator: user.operator,
      kind: kind,
      payload: {
        "subject" => event["subject"] || event["category"]&.first,
        "sg_event_id" => event["sg_event_id"],
        "sg_message_id" => event["sg_message_id"],
        "smtp_id" => event["smtp-id"],
        "url" => event["url"], # present on click events
      }.compact,
      occurred_at: event["timestamp"] ? Time.at(event["timestamp"]) : Time.current,
    )
  end

  def update_campaign_send_engagement(user, event_type)
    base = CampaignSend.where(user: user).where("created_at > ?", 30.days.ago)
    case event_type
    when "open"
      base.where(opened: false).update_all(opened: true, opened_at: Time.current)
    when "click"
      base.where(clicked: false).update_all(clicked: true, clicked_at: Time.current)
    end
  end
end
