module Campaigns
  # Window-based, last-touch attribution over the Activity timeline (CONTEXT.md
  # "Attribution"): a conversion within N days of a Person OPENING a campaign
  # email is credited to that campaign. Derived on read — no stored state —
  # mirroring Concierge::ConversionReport and the OfficeOutreach pattern.
  #
  #   Campaigns::AttributionReport.new(campaign).scorecard
  #   => { sent:, opened:, clicked:, converted:, revenue_cents: }
  #
  # Anchoring is consistent between the per-campaign scorecard and the per-person
  # timeline chip: a conversion counts when the Person opened this campaign within
  # the window BEFORE it — evaluated against EVERY open (so a multi-step drip's
  # later opens count, not just the first).
  class AttributionReport
    # "Money-bearing" conversions (David's call): a day pass, a membership, or an
    # office lease. NOT signups/tours.
    CONVERSION_KINDS = %w[day_pass subscription_started office_lease].freeze
    # Revenue is read from the canonical money event, which carries the amount.
    REVENUE_KIND = "payment_succeeded".freeze
    DEFAULT_WINDOW_DAYS = 14

    def initialize(campaign, window_days: DEFAULT_WINDOW_DAYS)
      @campaign = campaign
      @window_days = window_days
    end

    def scorecard
      opens = opens_by_user
      conversions = conversions_by_user(opens.keys)

      converted_ids = opens.keys.select do |user_id|
        (conversions[user_id] || []).any? { |at| opened_within_window_before?(opens[user_id], at) }
      end

      {
        sent: sends.sent.count,
        opened: sends.opened.count,
        clicked: sends.clicked.count,
        converted: converted_ids.size,
        # Revenue is credited ONLY to people who actually converted — otherwise
        # routine recurring dues from a non-converting opener would inflate it.
        revenue_cents: revenue_cents_for(converted_ids, opens),
      }
    end

    # For a Person's timeline: the campaign (if any) a conversion Activity is
    # attributed to — the most recent campaign the Person OPENED within the
    # window before the conversion (last-touch). Returns a Campaign or nil.
    # Pass `opened_sends:` (this user's opened CampaignSends, opened_at DESC,
    # campaign preloaded) to resolve in Ruby and avoid an N+1 across timeline rows.
    def self.campaign_for_conversion(activity, within_days: DEFAULT_WINDOW_DAYS, opened_sends: nil)
      return nil unless CONVERSION_KINDS.include?(activity.kind)

      window_start = activity.occurred_at - within_days.days
      if opened_sends
        opened_sends.find { |s| s.opened_at && s.opened_at >= window_start && s.opened_at <= activity.occurred_at }&.campaign
      else
        CampaignSend.where(user_id: activity.user_id, opened: true)
                    .where(opened_at: window_start..activity.occurred_at)
                    .order(opened_at: :desc)
                    .first
                    &.campaign
      end
    end

    private

    def sends
      @sends ||= @campaign.campaign_sends
    end

    # user_id => [opened_at, ...] (every open of THIS campaign; a drip has one per
    # opened step). The window is evaluated against all of them.
    def opens_by_user
      @opens_by_user ||= sends.opened.where.not(opened_at: nil)
                              .pluck(:user_id, :opened_at)
                              .group_by(&:first)
                              .transform_values { |rows| rows.map(&:last) }
    end

    def conversions_by_user(user_ids)
      return {} if user_ids.empty?

      Activity.where(user_id: user_ids, operator_id: @campaign.operator_id, kind: CONVERSION_KINDS)
              .pluck(:user_id, :occurred_at)
              .group_by(&:first)
              .transform_values { |rows| rows.map(&:last) }
    end

    # Sum of money-event amounts for CONVERTED users, within the window of one of
    # their opens. Org office leases don't emit payment_succeeded, so their $ isn't
    # counted here — they still count toward `converted`. (Individual leases invoice.)
    def revenue_cents_for(converted_ids, opens)
      return 0 if converted_ids.empty?

      Activity.where(user_id: converted_ids, operator_id: @campaign.operator_id, kind: REVENUE_KIND)
              .pluck(:user_id, :occurred_at, :payload)
              .sum do |user_id, occurred_at, payload|
        opened_within_window_before?(opens[user_id], occurred_at) ? amount_cents(payload) : 0
      end
    end

    def amount_cents(payload)
      payload ||= {}
      paid = payload["amount_paid"].to_i
      paid.positive? ? paid : payload["amount_due"].to_i
    end

    # True if `timestamp` falls within [open, open + window] for ANY of the opens.
    def opened_within_window_before?(user_opens, timestamp)
      return false if user_opens.blank?
      user_opens.any? { |opened_at| timestamp >= opened_at && timestamp <= opened_at + @window_days.days }
    end
  end
end
