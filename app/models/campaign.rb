class Campaign < ApplicationRecord
  belongs_to :operator
  belongs_to :location, optional: true

  has_many :campaign_steps, -> { order(:position) }, dependent: :destroy
  has_many :campaign_sends, dependent: :destroy

  acts_as_tenant :operator

  accepts_nested_attributes_for :campaign_steps, allow_destroy: true

  TYPES = %w[single drip].freeze
  STATUSES = %w[draft active paused completed cancelled].freeze
  CUSTOMER_TYPES = %w[day_pass membership office_lease room_booking].freeze

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

  def build_recipient_query(location)
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

      users = users.where(id: user_ids)
    end

    # Exclude opted-out, bounced, and marketing-suppressed
    users = users.where(email_opted_out: false, email_bounced: false, marketing_suppressed: false)

    users
  end

  def recipient_count_for(location)
    build_recipient_query(location).count
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
