
class UserMailer < ApplicationMailer
  helper ApplicationHelper
  helper LayoutHelper

  def password_reset(user, operator, reset_token = nil)
    @user = user
    @operator = operator
    @reset_token = reset_token || user.reset_token
    mail to: user.email, subject: "#{@operator.name} password reset", from: @operator.sender_from_address, reply_to: @operator.contact_email,
    'X-SMTPAPI' => {
      "filters" => {
        "clicktrack" => {
          "settings" => {
            "enable" => 0
          }
        },
        "opentrack" => {
          "settings" => {
            "enable" => 0
          }
        }
      }
    }.to_json
    recipients = User.superadmins.all.map {|u| u.email }
  end

  def email_confirmation(user, operator, token)
    @user = user
    @operator = operator
    @token = token
    mail to: user.email, subject: "Confirm your email for #{@operator.name}", from: @operator.sender_from_address, reply_to: @operator.contact_email,
    'X-SMTPAPI' => {
      "filters" => {
        "clicktrack" => {
          "settings" => {
            "enable" => 0
          }
        },
        "opentrack" => {
          "settings" => {
            "enable" => 0
          }
        }
      }
    }.to_json
  end

  def event_registration(user, password, event)
    @user = user
    @password = password
    @event = event

    @host = ENV['ASSET_HOST']
    mail to: @user.email, subject: "You're all set for #{@event.title}!", from: @user.operator.sender_from_address, reply_to: @user.operator.contact_email
  end

  def event_cancellation(user, event_name, operator)
    @user = user
    @event_name = event_name
    @operator = operator

    @host = ENV['ASSET_HOST']
    mail to: @user.email, subject: "Cancelled: #{@event_name}", from: @operator.sender_from_address, reply_to: @operator.contact_email
  end

  def announcement_email(announcement, recipient)
    @announcement = announcement
    @user = recipient
    @operator = announcement.operator
    @host = ENV['ASSET_HOST']
    reply_to = "#{announcement.user.name} <#{@operator.contact_email}>"
    mail to: recipient.email, subject: "Announcement from #{@operator.name}", from: @operator.sender_from_address, reply_to: reply_to
  end

  def onboarding_email(user, operator, password)
    @user = user
    @operator = operator
    @password = password
    @host = ENV['ASSET_HOST']
    mail to: user.email, subject: "Welcome to #{@operator.name}!", from: @operator.sender_from_address, reply_to: @operator.contact_email
  end

  def childcare_confirmation_email(childcare_reservation, user)
    @reservation = childcare_reservation
    @user = user
    @operator = user.operator
    @host = ENV['ASSET_HOST']
    mail to: user.email, subject: "Childcare confirmation", from: @operator.sender_from_address, reply_to: @operator.contact_email
  end

  def product_onboarding_email(user, operator, template, sendable)
    @user = user
    @operator = operator
    @template = template
    @sendable = sendable
    @host = ENV['ASSET_HOST']
    @processed_body = process_merge_tags(template, user, operator, sendable)
    mail to: user.email, subject: template.subject, from: operator.sender_from_address, reply_to: operator.contact_email
  end

  def product_follow_up_email(user, operator, template, sendable)
    @user = user
    @operator = operator
    @template = template
    @sendable = sendable
    @host = ENV['ASSET_HOST']
    @google_reviews_url = operator.google_reviews_url
    @processed_body = process_merge_tags(template, user, operator, sendable)
    mail to: user.email, subject: template.subject, from: operator.sender_from_address, reply_to: operator.contact_email
  end

  def payment_failed_email(user, operator, invoice)
    @user = user
    @operator = operator
    @invoice = invoice
    @host = ENV['ASSET_HOST']
    mail to: user.email, subject: "Action Required: Your recent payment failed", from: operator.sender_from_address, reply_to: operator.contact_email
  end

  def renewal_reminder_email(user, operator, subscription)
    @user = user
    @operator = operator
    @subscription = subscription
    @host = ENV['ASSET_HOST']
    mail to: user.email, subject: "Your membership renews soon", from: operator.sender_from_address, reply_to: operator.contact_email
  end

  def signup_nudge_email(user, operator, template)
    @user = user
    @operator = operator
    @template = template
    @host = ENV['ASSET_HOST']
    @processed_body = process_merge_tags(template, user, operator)
    mail to: user.email, subject: template.subject, from: operator.sender_from_address, reply_to: operator.contact_email
  end

  private

  def process_merge_tags(template, user, operator, sendable = nil)
    return "" if template.body.blank?
    body_html = template.body.to_s
    ProductEmailTemplate.replace_merge_tags(body_html, user: user, operator: operator, sendable: sendable).html_safe
  end
end
