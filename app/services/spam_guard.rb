# Central anti-spam invariant for marketing email sends.
#
# Per ADR-0003: a Person can be enrolled in at most one active series at a
# time (campaign OR multi-step automation), and a per-campaign cool-down
# excludes anyone who got an email from this operator within N days.
#
# Callers (Campaign#build_recipient_query, AutomatedWorkflowsJob handlers,
# User#enroll_in_welcome_drip!) consult SpamGuard.eligible? before sending
# or enqueueing. Transactional emails (password resets, booking confirms,
# etc.) bypass automatically — they don't call SpamGuard at all.
class SpamGuard
  # How far back a series enrollment counts as "still active." Welcome
  # drips and signup nurtures both run their final step around day 14,
  # so 60 days is a safe ceiling.
  ACTIVE_SERIES_LOOKBACK = 60.days

  def self.eligible?(user, sender:, cool_down_days: 30)
    return true if user.nil? || sender.nil?

    !in_active_drip?(user, sender) &&
      !in_welcome_drip?(user) &&
      !recently_emailed?(user, sender, cool_down_days.to_i)
  end

  # Returns false if the User received an email from this operator within
  # `cool_down_days`. A 0 cool-down means "no cool-down" (operator opted out).
  def self.recently_emailed?(user, sender, cool_down_days)
    return false if cool_down_days <= 0
    Activity.where(user: user, operator: sender, kind: "email_sent")
            .where("occurred_at > ?", cool_down_days.days.ago)
            .exists?
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
