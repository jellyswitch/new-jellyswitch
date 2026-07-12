require "net/smtp"

class ApplicationMailer < ActionMailer::Base
  # The platform sender is verified in SendGrid; brand senders are only
  # verified once their domain-authentication DNS records are in place.
  PLATFORM_FROM = "Jellyswitch <noreply@jellyswitch.com>"

  default from: PLATFORM_FROM
  layout 'mailer'

  after_action :log_email_sent

  # SendGrid 550s any mail whose From domain isn't a verified Sender Identity
  # (a brand whose domain authentication isn't set up yet), which bounces
  # every email for that brand — confirmations, password resets, receipts.
  # Retry once from the platform sender, keeping the brand reachable via
  # Reply-To. Once the brand's domain is authenticated the first attempt
  # succeeds and this never fires.
  def self.deliver_mail(mail)
    super
  rescue Net::SMTPFatalError => e
    raise unless e.message.include?("verified Sender Identity")

    original_from = mail[:from].to_s
    raise if original_from.include?("noreply@jellyswitch.com")

    if defined?(Honeybadger)
      Honeybadger.notify(
        "Unverified SendGrid sender — delivered from platform fallback",
        context: { original_from: original_from, to: mail.to, subject: mail.subject, smtp_error: e.message },
      )
    end

    mail.reply_to = original_from if mail.reply_to.blank?
    mail.from = PLATFORM_FROM
    super(mail)
  end

  private

  # Log every outbound email as an Activity on the recipient's timeline.
  # Per CONTEXT.md: campaign, automation, AND transactional (receipts,
  # password resets, booking confirmations) all count — operators care
  # about total contact volume, not just marketing volume.
  #
  # Best-effort: a failure here must never block email delivery.
  def log_email_sent
    return if message.to.blank?

    recipient_email = Array(message.to).first
    return if recipient_email.blank?

    user, operator = resolve_recipient_and_operator(recipient_email)
    return unless user && operator

    Activity.log(
      user: user,
      operator: operator,
      kind: :email_sent,
      payload: {
        "subject" => message.subject,
        "to" => recipient_email,
        "mailer" => self.class.name,
        "action" => action_name,
      },
    )
  rescue StandardError => e
    Rails.logger.error("ActivityLogger from mailer failed: #{e.class}: #{e.message}")
    Honeybadger.notify(e) if defined?(Honeybadger)
  end

  def resolve_recipient_and_operator(recipient_email)
    explicit_user = instance_variable_get(:@user)
    explicit_operator = instance_variable_get(:@operator)

    user = explicit_user.is_a?(User) && explicit_user.persisted? ? explicit_user : nil
    operator = explicit_operator.is_a?(Operator) && explicit_operator.persisted? ? explicit_operator : nil

    if user.nil?
      user = if operator
        User.find_by(email: recipient_email, operator: operator)
      else
        User.find_by(email: recipient_email)
      end
    end

    operator ||= user&.operator

    [user, operator]
  end
end
