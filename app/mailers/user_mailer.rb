
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

  # Passwordless "login code" (OTP) — ADR 0016. Transactional, so it's exempt
  # from the Spam Guard cool-down (ADR 0003) and always sends. Click/open
  # tracking disabled (a 6-digit code email has no links worth tracking, and we
  # don't want SendGrid rewriting it).
  def login_code(user, operator, code)
    @user = user
    @operator = operator
    @code = code
    mail to: user.email, subject: "Your #{@operator.name} login code: #{@code}", from: @operator.sender_from_address, reply_to: @operator.contact_email,
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

  # Step 2 of the non-payment drip (PaymentCutoff): 48h after the failure
  # notice, warn that access pauses in another 48h.
  def payment_cutoff_warning_email(user, operator, invoice, location = nil)
    @user = user
    @operator = operator
    @invoice = invoice
    @location = location
    @host = ENV['ASSET_HOST']
    from_address = location&.sender_from_address || operator.sender_from_address
    mail to: user.email, subject: "Action Required: Your access will be paused in 48 hours", from: from_address, reply_to: operator.contact_email
  end

  # Step 3 of the non-payment drip (PaymentCutoff): access is now paused;
  # paying the invoice restores it instantly.
  def payment_suspended_email(user, operator, invoice, location = nil)
    @user = user
    @operator = operator
    @invoice = invoice
    @location = location
    @host = ENV['ASSET_HOST']
    from_address = location&.sender_from_address || operator.sender_from_address
    mail to: user.email, subject: "Your access is paused — settle your balance to restore it", from: from_address, reply_to: operator.contact_email
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

  # Confirms a NEW membership at signup. Hardcoded + always fires (via
  # Billing::Subscription::SendMembershipWelcome) so a new member always gets a
  # confirmation, independent of any operator-configured onboarding template.
  # The payment receipt itself is left to Stripe's "Successful payments" emails.
  def membership_welcome_email(user, operator, subscription, location = nil)
    @user = user
    @operator = operator
    @subscription = subscription
    @plan = subscription&.plan
    @location = location
    @host = ENV['ASSET_HOST']
    from_address = location&.sender_from_address || operator.sender_from_address
    mail to: user.email, subject: "Welcome to #{operator.name}", from: from_address, reply_to: operator.contact_email
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
  def membership_cancellation_email(user, operator, subscription, location = nil, immediate: false, commitment_ends_on: nil)
    @user = user
    @operator = operator
    @subscription = subscription
    @location = location
    @immediate = immediate
    # A commitment cancel keeps the membership — and its regular billing —
    # running through the commitment boundary, so the template must not promise
    # "you won't be billed again"; it gets its own wording keyed on this date.
    @commitment_ends_on = commitment_ends_on
    # For a scheduled cancel, access continues through the paid period.
    # current_period_end reads from Stripe and is nil for $0/no-Stripe plans.
    @ends_on = immediate ? nil : (commitment_ends_on || subscription.current_period_end)
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

  # Heads-up to the OPERATOR that a fixed-term (non-auto-renew) office lease is
  # approaching its end date. Sent by LeaseRenewalReminderJob within the lease's
  # renewal-notice window, once per term — so a lease can't silently lapse.
  def lease_expiring_operator_email(operator, office_lease, location = nil)
    @operator = operator
    @office_lease = office_lease
    @location = location
    @office_name = office_lease.office_name
    @leasee_name = office_lease.leasee_name
    @ends_on = office_lease.end_date
    @host = ENV['ASSET_HOST']
    from_address = location&.sender_from_address || operator.sender_from_address
    mail to: operator.contact_email,
         subject: "Lease ending soon: #{@office_name} (#{@leasee_name})",
         from: from_address, reply_to: operator.contact_email
  end

  # Heads-up to the LESSEE that their fixed-term office lease is ending and is
  # not set to auto-renew, so they can reach out to renew before it lapses.
  def lease_expiring_lessee_email(user, operator, office_lease, location = nil)
    @user = user
    @operator = operator
    @office_lease = office_lease
    @location = location
    @office_name = office_lease.office_name
    @ends_on = office_lease.end_date
    @host = ENV['ASSET_HOST']
    from_address = location&.sender_from_address || operator.sender_from_address
    mail to: user.email,
         subject: "Your office lease for #{@office_name} ends #{office_lease.pretty_date}",
         from: from_address, reply_to: operator.contact_email
  end

  # Confirms a day-pass date change to the pass holder. Sent from both the
  # member-facing API reschedule and the staff move in web admin — for the
  # staff path this is the only way the member finds out.
  def day_pass_rescheduled(day_pass_id, old_day)
    day_pass = DayPass.find_by(id: day_pass_id)
    return if day_pass.nil? || day_pass.user.nil?

    @user = day_pass.user
    @day_pass = day_pass
    @location = day_pass.location
    @operator = day_pass.operator || @location&.operator
    @old_day = old_day.to_date
    @host = ENV['ASSET_HOST']
    @unsubscribe_url = unsubscribe_url(@user)
    # Day Office pass (ADR 0026): the reschedule already moved the hold
    # (DayOffices::MoveHold), so the view can name the room on the NEW date.
    # nil for a standard pass, which never has a hold.
    @office_hold = day_pass.office_hold
    from_address = @location&.sender_from_address || @operator.sender_from_address

    mail to: @user.email,
         subject: "Your day pass is now scheduled for #{@day_pass.day.strftime('%B %-e, %Y')}",
         from: from_address, reply_to: @operator.contact_email
  end

  # Confirms a Day Office assignment to the pass holder (ADR 0026) — which
  # room, when, and where. Sent as the FINAL step of every purchase organizer
  # (Billing::DayPasses::NotifyDayOfficeAssigned), so it only ever goes out
  # after money actually moved, and from the bundle burn paths where the pass
  # is already prepaid.
  #
  # No hold means nothing to confirm: the assignment was released between
  # enqueue and delivery (refund, reschedule, staff restore). Bail rather than
  # promise a room the member no longer has.
  def day_office_confirmation(day_pass_id)
    day_pass = DayPass.find_by(id: day_pass_id)
    return if day_pass.nil? || day_pass.user.nil?

    @office_hold = day_pass.office_hold
    return if @office_hold.nil?

    @user = day_pass.user
    @day_pass = day_pass
    @room = @office_hold.room
    @location = day_pass.location
    @operator = day_pass.operator || @location&.operator
    return if @operator.nil?

    @host = ENV['ASSET_HOST']
    @unsubscribe_url = unsubscribe_url(@user)
    from_address = @location&.sender_from_address || @operator.sender_from_address

    mail to: @user.email,
         subject: "Your Day Office: #{@room.name} on #{day_pass.day.strftime('%B %-e')}",
         from: from_address, reply_to: @operator.contact_email
  end

  # Tells the member their Day Office moved to a different room (Task 12).
  # Takes the NEW hold plus the old room's name — a string, not an id, because
  # by the time this runs the move is done and the old room may be occupied by
  # someone else.
  def day_office_reassigned(reservation_id, old_room_name)
    hold = Reservation.find_by(id: reservation_id)
    return if hold.nil? || hold.user.nil? || hold.room.nil?

    @hold = hold
    @user = hold.user
    @room = hold.room
    @old_room_name = old_room_name.presence
    @location = hold.room.location
    @operator = @location&.operator
    return if @operator.nil?

    @day = hold.datetime_in.to_date
    @host = ENV['ASSET_HOST']
    @unsubscribe_url = unsubscribe_url(@user)
    from_address = @location&.sender_from_address || @operator.sender_from_address

    mail to: @user.email,
         subject: "Your office for #{@day.strftime('%B %-e')} is now #{@room.name}",
         from: from_address, reply_to: @operator.contact_email
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

    body_html = replace_blob_urls(body_html, host: host)

    ProductEmailTemplate.replace_merge_tags(body_html, user: user, operator: operator, location: location, sendable: sendable, host: host).html_safe
  end

  # Rehost embedded ActiveStorage images/links onto a real app host.
  #
  # Rendering a rich-text body outside a request (this mailer runs from
  # Sidekiq) makes ActionText emit ABSOLUTE URLs on the renderer's placeholder
  # host — literally https://example.org/rails/active_storage/… — so every
  # embedded image shipped broken (Cowork Tahoe's space map, 2026-08). The
  # previous version of this method only matched relative "/rails/…" paths, so
  # it never fired on what ActionText actually emits; and rewriting to
  # blob.url would break differently — that's a presigned S3 URL that expires
  # minutes after render, long before most recipients open the email.
  #
  # Keeping the app's own redirect URL is the durable choice: the signed ids
  # inside it never expire (exp:null), and each open 302s to a
  # freshly-presigned S3 URL. Only the host needs fixing.
  BLOB_URL_PATTERN = %r{(href|src)="(?:https?://[^/"]+)?(/rails/active_storage/(?:blobs|representations)/(?:redirect|proxy)/[^"]+)"}

  def replace_blob_urls(html, host: ENV['ASSET_HOST'])
    return html if host.blank?

    html.gsub(BLOB_URL_PATTERN) { "#{$1}=\"#{host.chomp('/')}#{$2}\"" }
  end
end
