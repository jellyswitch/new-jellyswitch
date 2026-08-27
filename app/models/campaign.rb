# == Schema Information
#
# Table name: campaigns
#
#  id               :bigint(8)        not null, primary key
#  campaign_type    :string           default("single"), not null
#  cool_down_days   :integer          default(30), not null
#  name             :string           not null
#  recipient_count  :integer          default(0)
#  scheduled_at     :datetime
#  segment          :jsonb            not null
#  sent_at          :datetime
#  status           :string           default("draft"), not null
#  suppression_days :integer          default(7)
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  location_id      :bigint(8)
#  operator_id      :bigint(8)        not null
#
# Indexes
#
#  index_campaigns_on_location_id  (location_id)
#  index_campaigns_on_operator_id  (operator_id)
#
class Campaign < ApplicationRecord
  belongs_to :operator
  belongs_to :location, optional: true

  has_many :campaign_steps, -> { order(:position) }, dependent: :destroy
  has_many :campaign_sends, dependent: :destroy

  acts_as_tenant :operator

  accepts_nested_attributes_for :campaign_steps, allow_destroy: true

  TYPES = %w[single drip].freeze
  STATUSES = %w[draft active paused completed cancelled].freeze
  # tour_request / concierge_chat are LEAD segments: people captured by the
  # embed widgets (Activity kinds :tour_request / :chat), not yet customers.
  CUSTOMER_TYPES = %w[day_pass membership office_lease room_booking tour_request concierge_chat].freeze

  validates :name, presence: true
  validates :campaign_type, inclusion: { in: TYPES }
  validates :status, inclusion: { in: STATUSES }

  scope :draft, -> { where(status: "draft") }
  scope :active, -> { where(status: "active") }

  def single?
    campaign_type == "single"
  end

  def drip?
    campaign_type == "drip"
  end

  def draft?
    status == "draft"
  end

  def active?
    status == "active"
  end

  def paused?
    status == "paused"
  end

  def completed?
    status == "completed"
  end

  def cancelled?
    status == "cancelled"
  end

  def excluded_user_ids
    segment["excluded_user_ids"] || []
  end

  def exclude_user!(user_id)
    ids = excluded_user_ids
    ids << user_id unless ids.include?(user_id)
    self.segment = segment.merge("excluded_user_ids" => ids)
    save!
  end

  def include_user!(user_id)
    ids = excluded_user_ids - [user_id]
    self.segment = segment.merge("excluded_user_ids" => ids)
    save!
  end

  def segment_customer_types
    segment["customer_types"] || []
  end

  def segment_date_range
    from = segment.dig("date_range", "from")
    to = segment.dig("date_range", "to")
    return nil unless from.present? && to.present?
    Date.parse(from)..Date.parse(to)
  end

  def segment_status_filter
    segment["status_filter"] || "all"
  end

  # Interest-tag audience (ADR 0022). Restricted to known products so stray
  # segment data can't widen the query. "any" (default) vs "all" match.
  def segment_interest_products
    (segment["interest_products"] || []) & InterestTag::PRODUCTS
  end

  def segment_interest_match
    segment["interest_match"] == "all" ? "all" : "any"
  end

  def build_recipient_query(location, apply_spam_guard: true)
    users = User.for_space(operator).visible
    users = users.originally_at_location(location) if location

    # Filter by customer type
    types = segment_customer_types
    if types.any?
      user_ids = Set.new
      date_range = segment_date_range

      if types.include?("day_pass")
        scope = DayPass.joins(:user).where(users: { operator_id: operator.id })
        scope = scope.where(created_at: date_range) if date_range
        user_ids.merge(scope.pluck(:user_id))
      end

      if types.include?("membership")
        scope = Subscription.joins(:user).where(users: { operator_id: operator.id })
        scope = scope.where(created_at: date_range) if date_range
        if segment_status_filter == "active"
          scope = scope.active
        end
        user_ids.merge(scope.pluck(:user_id))
      end

      if types.include?("office_lease")
        scope = OfficeLease.joins(:user).where(users: { operator_id: operator.id })
        scope = scope.where(created_at: date_range) if date_range
        user_ids.merge(scope.pluck(:user_id))
      end

      if types.include?("room_booking")
        scope = Reservation.joins(:user).where(users: { operator_id: operator.id })
        scope = scope.where(created_at: date_range) if date_range
        user_ids.merge(scope.pluck(:user_id))
      end

      # Widget-lead segments come off the Activity timeline (occurred_at, not
      # created_at — backfilled activities keep their real date).
      if types.include?("tour_request")
        scope = Activity.where(operator_id: operator.id, kind: "tour_request")
        scope = scope.where(occurred_at: date_range) if date_range
        user_ids.merge(scope.pluck(:user_id))
      end

      if types.include?("concierge_chat")
        scope = Activity.where(operator_id: operator.id, kind: "chat")
        scope = scope.where(occurred_at: date_range) if date_range
        user_ids.merge(scope.pluck(:user_id))
      end

      users = users.where(id: user_ids)
    end

    # Filter by interest tag (ADR 0022) — an independent axis ANDed with the
    # customer-type filter above. "any" holds one of the products; "all" holds
    # every one (the "viewed day pass AND membership" play).
    interest_products = segment_interest_products
    if interest_products.any?
      interest_scope = segment_interest_match == "all" ? User.with_all_interests(interest_products) : User.with_any_interest(interest_products)
      users = users.where(id: interest_scope.select(:id))
    end

    # Never send to the unsubscribed / bounced / operator-suppressed.
    users = users.marketing_sendable

    # Exclude per-campaign exclusions
    excluded = excluded_user_ids
    users = users.where.not(id: excluded) if excluded.any?

    # Apply Spam Guard (ADR-0003): drop anyone in another active series or
    # cooled down on this operator. Set apply_spam_guard: false for preview
    # callers that want the raw candidate pool. Load candidates once (was an
    # N+1: a User.find per id).
    if apply_spam_guard
      ineligible_ids = users.to_a.reject do |candidate|
        SpamGuard.eligible?(candidate, sender: operator, cool_down_days: cool_down_days)
      end.map(&:id)
      users = users.where.not(id: ineligible_ids) if ineligible_ids.any?
    end

    users
  end

  def recipient_count_for(location)
    build_recipient_query(location).count
  end

  # Number of candidates excluded by Spam Guard at compose time.
  def spam_guard_excluded_count_for(location)
    raw = build_recipient_query(location, apply_spam_guard: false).count
    filtered = build_recipient_query(location, apply_spam_guard: true).count
    raw - filtered
  end

  def clone!
    dup.tap do |c|
      c.name = "#{name} (copy)"
      c.status = "draft"
      c.sent_at = nil
      c.scheduled_at = nil
      c.recipient_count = 0
      c.save!
      campaign_steps.each do |step|
        c.campaign_steps.create!(step.attributes.except("id", "campaign_id", "created_at", "updated_at", "sent_count"))
      end
    end
  end
end
