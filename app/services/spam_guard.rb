# Central anti-spam invariant for marketing email sends.
#
# Per ADR-0003: a Person can be enrolled in at most one active series at a
# time (campaign OR multi-step automation), and a per-campaign cool-down
# excludes anyone who got a *marketing* email from this operator within N days.
#
# The cool-down throttles marketing fatigue — it must NOT count transactional
# mail (account confirmation, receipts, password resets). Counting those was a
# regression: every brand-new signup gets a confirmation email, so a cool-down
# that counted it silently suppressed the very drip/nudge it was supposed to
# start. The guard's job is "one active series at a time + don't stack
# marketing," not "any contact pauses all marketing."
#
# Callers (Campaign#build_recipient_query, AutomatedWorkflowsJob handlers,
# User#enroll_in_welcome_drip!) consult SpamGuard.eligible? before sending
# or enqueueing. Transactional emails bypass automatically — they don't call
# SpamGuard at all, and (per the cool-down change above) don't count toward it.
class SpamGuard
  # How far back a series enrollment counts as "still active." Welcome
  # drips and signup nurtures both run their final step around day 14,
  # so 60 days is a safe ceiling.
  ACTIVE_SERIES_LOOKBACK = 60.days

  # ProductEmailSend email_types that are NOT marketing/series sends, so they
  # must not consume the cool-down: `onboarding` is transactional (operationally
  # required, and already bypasses SpamGuard on the way out), and
  # `welcome_drip_enrolled` is an enrollment marker row, not an email.
  NON_MARKETING_EMAIL_TYPES = ["onboarding", User::WELCOME_DRIP_ENROLLED_KEY].freeze

  def self.eligible?(user, sender:, cool_down_days: 30)
    return true if user.nil? || sender.nil?

    !in_active_drip?(user, sender) &&
      !in_welcome_drip?(user) &&
      !recently_emailed?(user, sender, cool_down_days.to_i)
  end

  # Returns false if the User received a *marketing* email (drip / campaign /
  # automation step / product nudge or follow-up) from this operator within
  # `cool_down_days`. Sourced from the marketing send ledgers (ProductEmailSend
  # + CampaignSend), NOT the catch-all `email_sent` Activity log, so
  # transactional mail never trips it. A 0 cool-down means "no cool-down."
  def self.recently_emailed?(user, sender, cool_down_days)
    return false if cool_down_days <= 0
    since = cool_down_days.days.ago

    marketing_product_send =
      ProductEmailSend.where(user: user, operator: sender, status: "sent")
                      .where.not(email_type: NON_MARKETING_EMAIL_TYPES)
                      .where("product_email_sends.created_at > ?", since)
                      .exists?

    marketing_campaign_send =
      CampaignSend.joins(:campaign)
                  .where(user: user, status: "sent")
                  .where(campaigns: { operator_id: sender.id })
                  .where("campaign_sends.created_at > ?", since)
                  .exists?

    marketing_product_send || marketing_campaign_send
  end

  # Returns true if the User is currently enrolled in any active drip
  # campaign owned by this operator (sent_at within ACTIVE_SERIES_LOOKBACK).
  def self.in_active_drip?(user, sender)
    CampaignSend.joins(:campaign)
                .where(user: user)
                .where(campaigns: { operator_id: sender.id, campaign_type: "drip", status: "active" })
                .where("campaign_sends.sent_at > ?", ACTIVE_SERIES_LOOKBACK.ago)
                .exists?
  end

  # Returns true if the user is currently enrolled in the Welcome Drip
  # multi-step automation (within ACTIVE_SERIES_LOOKBACK).
  def self.in_welcome_drip?(user)
    ProductEmailSend.where(sendable_type: "User", sendable_id: user.id,
                           email_type: User::WELCOME_DRIP_ENROLLED_KEY)
                    .where("created_at > ?", ACTIVE_SERIES_LOOKBACK.ago)
                    .exists?
  end
end
