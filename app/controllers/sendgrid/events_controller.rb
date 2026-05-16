# Receives Sendgrid Event Webhook POSTs and routes them into the activity
# timeline + User email-status flags.
#
# Configure in Sendgrid: Settings → Mail Settings → Event Webhook.
# Webhook URL: https://<your-host>/sendgrid/events
# Auth (optional but recommended): set SENDGRID_WEBHOOK_USERNAME and
# SENDGRID_WEBHOOK_PASSWORD env vars; in Sendgrid use the HTTP Basic auth
# fields. When the env vars are unset (dev/test), requests are accepted
# without authentication.
class Sendgrid::EventsController < ApplicationController
  skip_before_action :verify_authenticity_token, raise: false
  skip_forgery_protection

  ENGAGEMENT_KINDS = {
    "open" => "email_opened",
    "click" => "email_clicked",
  }.freeze

  def receive
    return head :unauthorized unless authenticated?
    events = parse_events
    return head :bad_request if events.nil?
    events.each { |event| handle_event(event) }
    head :ok
  end

  private

  def authenticated?
    expected_user = ENV["SENDGRID_WEBHOOK_USERNAME"]
    expected_pass = ENV["SENDGRID_WEBHOOK_PASSWORD"]
    return true if expected_user.blank? || expected_pass.blank?

    authenticate_with_http_basic do |u, p|
      ActiveSupport::SecurityUtils.secure_compare(u, expected_user) &&
        ActiveSupport::SecurityUtils.secure_compare(p, expected_pass)
    end
  end

  def parse_events
    body = request.body.read
    return [] if body.blank?
    parsed = JSON.parse(body)
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
