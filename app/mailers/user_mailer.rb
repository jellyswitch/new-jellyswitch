
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

  # Commitment-term renewal notice: sent `commitment_notice_days` (default 30)
  # before a committed membership's term re-arms — the member's opt-out window.
  def commitment_renewal_email(user, operator, subscription, location = nil)
    @user = user
    @operator = operator
    @subscription = subscription
    @location = location
    @ends_on = subscription.commitment_term_end
    @host = ENV['ASSET_HOST']
    from_address = location&.sender_from_address || operator.sender_from_address
    mail to: user.email, subject: "Your membership commitment renews soon",
         from: from_address, reply_to: operator.contact_email
  end

  # Sent when a member cancels their membership -- either immediately
  # (immediate: true) or scheduled for the end of the current billing
  # period (immediate: false). A cancelling member must get this instead
  # of the renewal reminder, which previously still fired because a
  # cancel-at-period-end subscription stays active: true until the period ends.
  def membership_cancellation_email(user, operator, subscription, location = nil, immediate: false)
    @user = user
    @operator = operator
    @subscription = subscription
    @location = location
    @immediate = immediate
    # For a scheduled cancel, access continues through the paid period.
    # current_period_end reads from Stripe and is nil for $0/no-Stripe plans.
    @ends_on = immediate ? nil : subscription.current_period_end
    @host = ENV['ASSET_HOST']
    from_address = location&.sender_from_address || operator.sender_from_address
    subject = immediate ? "Your membership has been canceled" : "Your membership cancellation is confirmed"
    mail to: user.email, subject: subject, from: from_address, reply_to: operator.contact_email
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

  def re_engagement_email(user, operator, template, location = nil)
    @user = user
    @operator = operator
    @location = location
    @host = ENV['ASSET_HOST']
    @processed_body = process_merge_tags(template, user, operator, nil, location)
    @unsubscribe_url = unsubscribe_url(user)
    from_address = location&.sender_from_address || operator.sender_from_address
    mail to: user.email, subject: template.subject, from: from_address, reply_to: operator.contact_email
  end

  def past_due_followup_email(user, operator, invoice, location = nil)
    @user = user
    @operator = operator
    @invoice = invoice
    @location = location
    @host = ENV['ASSET_HOST']
    @unsubscribe_url = unsubscribe_url(user)
    from_address = location&.sender_from_address || operator.sender_from_address
    mail to: user.email, subject: "Reminder: Payment past due", from: from_address, reply_to: operator.contact_email
  end

  # Sent by Reservations::MarkPaymentFailed when an authorize-hold or
  # capture step on a reservation fails. Lets the member know their
  # card didn't go through and prompts them to update payment info
  # or contact the operator.
  def reservation_payment_failed(reservation_id, reason = nil)
    reservation = Reservation.unscoped.find_by(id: reservation_id)
    return if reservation.nil?

    @user = reservation.user
    @reservation = reservation
    @location = reservation.room.location
    @operator = @location.operator
    @reason = reason.to_s.first(200)
    @host = ENV['ASSET_HOST']
    @unsubscribe_url = unsubscribe_url(@user)
    from_address = @location&.sender_from_address || @operator.sender_from_address

    mail to: @user.email,
         subject: "Action needed: payment for your meeting room booking",
         from: from_address,
         reply_to: @operator.contact_email
  end

  # Sent by Billing::Reservations::CaptureHold and ChargeExtensionDelta
  # right after a successful capture, so the member has a paper trail
  # of the actual charge. `kind` is :capture (default) or :extension —
  # the only behavioral difference is the subject line.
  def meeting_room_charged(reservation_id, amount_cents, kind: :capture)
    reservation = Reservation.find_by(id: reservation_id)
    return if reservation.nil?

    @user = reservation.user
    @operator = reservation.room.location.operator
    @location = reservation.room.location
    @reservation = reservation
    @amount_cents = amount_cents.to_i
    @kind = kind
    @host = ENV['ASSET_HOST']
    @unsubscribe_url = unsubscribe_url(@user)
    from_address = @location&.sender_from_address || @operator.sender_from_address

    subject = kind == :extension ?
      "Receipt: Meeting room extension — $#{format('%.2f', @amount_cents / 100.0)}" :
      "Receipt: #{@reservation.room.name} — $#{format('%.2f', @amount_cents / 100.0)}"

    mail to: @user.email, subject: subject, from: from_address, reply_to: @operator.contact_email
  end

  # Resends a receipt to the customer for an existing invoice. Triggered
  # manually by an admin via the "Email receipt to customer" button when
  # a member asks for a copy. Body includes the Stripe-hosted receipt
  # URL (or Stripe Invoice PDF for subscription-backed invoices), where
  # the customer can hit Stripe's own Download as PDF.
  def invoice_receipt_email(invoice)
    @invoice = invoice
    @operator = invoice.operator
    @location = invoice.location
    @recipient_email = invoice.billable.email
    @amount_cents = invoice.amount_paid.to_i.nonzero? || invoice.amount_due.to_i
    @receipt_url = invoice.pdf_url
    @host = ENV['ASSET_HOST']

    from_address = @location&.sender_from_address || @operator.sender_from_address
    subject = "Your receipt from #{@operator.name} — $#{format('%.2f', @amount_cents / 100.0)}"

    mail to: @recipient_email, subject: subject, from: from_address, reply_to: @operator.contact_email
  end

  def booking_reminder_email(user, operator, reservation, location = nil)
    @user = user
    @operator = operator
    @reservation = reservation
    @location = location
    @host = ENV['ASSET_HOST']
    @unsubscribe_url = unsubscribe_url(user)
    from_address = location&.sender_from_address || operator.sender_from_address

    # Attach .ics calendar file
    ics = generate_ics(reservation, operator)
    attachments["reservation.ics"] = { mime_type: "text/calendar", content: ics }

    mail to: user.email, subject: "Reminder: Your room reservation tomorrow", from: from_address, reply_to: operator.contact_email
  end

  def campaign_email(user, operator, campaign_step, location = nil)
    @user = user
    @operator = operator
    @campaign_step = campaign_step
    @location = location
    @host = ENV['ASSET_HOST']
    @body = campaign_step.body
      .gsub("{{first_name}}", user.name.split.first)
      .gsub("{{full_name}}", user.name)
      .gsub("{{space_name}}", operator.name)
    @unsubscribe_url = unsubscribe_url(user)
    from_address = location&.sender_from_address || operator.sender_from_address
    mail to: user.email, subject: campaign_step.subject, from: from_address, reply_to: operator.contact_email
  end

  private

  def unsubscribe_url(user)
    token = Rails.application.message_verifier(:unsubscribe).generate(user.id, expires_in: 1.year)
    "#{ENV['ASSET_HOST']}/unsubscribe/#{token}"
  end

  def generate_ics(reservation, operator)
    dtstart = reservation.datetime_in.utc.strftime("%Y%m%dT%H%M%SZ")
    dtend = reservation.datetime_out.utc.strftime("%Y%m%dT%H%M%SZ")
    uid = "reservation-#{reservation.id}@#{operator.subdomain}.jellyswitch.com"
    summary = "#{reservation.room.name} — #{operator.name}"
    location_text = operator.building_address.presence || operator.name

    <<~ICS
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//Jellyswitch//Reservation//EN
      BEGIN:VEVENT
      UID:#{uid}
      DTSTART:#{dtstart}
      DTEND:#{dtend}
      SUMMARY:#{summary}
      LOCATION:#{location_text}
      DESCRIPTION:Meeting room reservation at #{operator.name}
      END:VEVENT
      END:VCALENDAR
    ICS
  end

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
