
class UserMailer < ApplicationMailer
  helper ApplicationHelper
  helper LayoutHelper

  def password_reset(user, operator, reset_token = nil)
    @user = user
    @operator = operator
    @reset_token = reset_token || user.reset_token

    if @reset_token.blank?
      Rails.logger.error("PasswordReset: reset_token is nil for user #{user.id} (#{user.email})")
      Honeybadger.notify("Password reset token is nil", context: { user_id: user.id, email: user.email, operator_id: operator.id })
      return
    end

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
    @location = announcement.location
    @host = ENV['ASSET_HOST']
    reply_to = "#{announcement.user.name} <#{@operator.contact_email}>"
    from_address = @location&.sender_from_address || @operator.sender_from_address
    mail to: recipient.email, subject: "Announcement from #{@location&.name || @operator.name}", from: from_address, reply_to: reply_to
  end

  def childcare_confirmation_email(childcare_reservation, user)
    @reservation = childcare_reservation
    @user = user
    @operator = user.operator
    @host = ENV['ASSET_HOST']
    mail to: user.email, subject: "Childcare confirmation", from: @operator.sender_from_address, reply_to: @operator.contact_email
  end

  def product_onboarding_email(user, operator, template, sendable, location = nil)
    @user = user
    @operator = operator
    @template = template
    @sendable = sendable
    @location = location
    @host = ENV['ASSET_HOST']
    @processed_body = process_merge_tags(template, user, operator, sendable, location)
    from_address = location&.sender_from_address || operator.sender_from_address
    mail to: user.email, subject: template.subject, from: from_address, reply_to: operator.contact_email
  end

  def product_follow_up_email(user, operator, template, sendable, location = nil)
    @user = user
    @operator = operator
    @template = template
    @sendable = sendable
    @location = location
    @host = ENV['ASSET_HOST']
    @google_reviews_url = location&.effective_google_reviews_url || operator.google_reviews_url
    @processed_body = process_merge_tags(template, user, operator, sendable, location)
    from_address = location&.sender_from_address || operator.sender_from_address
    mail to: user.email, subject: template.subject, from: from_address, reply_to: operator.contact_email
  end

  def payment_failed_email(user, operator, invoice, location = nil)
    @user = user
    @operator = operator
    @invoice = invoice
    @location = location
    @host = ENV['ASSET_HOST']
    from_address = location&.sender_from_address || operator.sender_from_address
    mail to: user.email, subject: "Action Required: Your recent payment failed", from: from_address, reply_to: operator.contact_email
  end

  def renewal_reminder_email(user, operator, subscription, location = nil)
    @user = user
    @operator = operator
    @subscription = subscription
    @location = location
    @host = ENV['ASSET_HOST']
    from_address = location&.sender_from_address || operator.sender_from_address
    mail to: user.email, subject: "Your membership renews soon", from: from_address, reply_to: operator.contact_email
  end

  def lease_renewal_proposal_email(user, operator, renewal_request, location = nil)
    @user = user
    @operator = operator
    @request = renewal_request
    @location = location
    @host = ENV['ASSET_HOST']
    from_address = location&.sender_from_address || operator.sender_from_address
    mail to: user.email, subject: "Your office lease renewal for #{renewal_request.office_lease.office.name}", from: from_address, reply_to: operator.contact_email
  end

  def signup_nudge_email(user, operator, template, location = nil)
    @user = user
    @operator = operator
    @template = template
    @location = location
    @host = ENV['ASSET_HOST']
    @processed_body = process_merge_tags(template, user, operator, nil, location)
    from_address = location&.sender_from_address || operator.sender_from_address
    mail to: user.email, subject: template.subject, from: from_address, reply_to: operator.contact_email
  end

  private

  def process_merge_tags(template, user, operator, sendable = nil, location = nil)
    return "" if template.body.blank?
    body_html = template.body.to_s
    host = ENV['ASSET_HOST']

    # Replace relative ActiveStorage blob URLs with absolute service URLs
    # so attachments work in email clients
    body_html = replace_blob_urls(body_html)

    ProductEmailTemplate.replace_merge_tags(body_html, user: user, operator: operator, location: location, sendable: sendable, host: host).html_safe
  end

  def replace_blob_urls(html)
    # Match ActiveStorage blob URLs (redirect, proxy, or representation patterns)
    html.gsub(%r{(href|src)="(/rails/active_storage/(?:blobs|representations)/(?:redirect|proxy)/([^/]+)/[^"]+)"}) do
      attr = $1
      path = $2
      signed_id = $3
      begin
        blob = ActiveStorage::Blob.find_signed(signed_id)
        if blob
          "#{attr}=\"#{blob.url}\""
        else
          "#{attr}=\"#{path}\""
        end
      rescue => e
        Rails.logger.error("Blob URL replacement error: #{e.message}")
        "#{attr}=\"#{path}\""
      end
    end
  end
end
