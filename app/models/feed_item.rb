
# == Schema Information
#
# Table name: feed_items
#
#  id          :bigint(8)        not null, primary key
#  blob        :jsonb            not null
#  expense     :boolean          default(FALSE), not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  location_id :integer
#  operator_id :integer          not null
#  user_id     :integer
#
# Indexes
#
#  index_feed_items_on_blob         (blob) USING gin
#  index_feed_items_on_location_id  (location_id)
#

class FeedItem < ApplicationRecord
  include HasLocation

  MONTHS = [["Select Month", ""], ["January", 1], ["February", 2], ["March", 3], ["April", 4], ["May", 5], ["June", 6], ["July", 7], ["August", 8], ["September", 9], ["Octobor", 10], ["November", 11], ["December", 12]]
  searchkick
  has_many_attached :photos
  # Relationships
  belongs_to :operator
  belongs_to :user
  has_many :feed_item_comments

  # Override partial path so Turbo broadcasts find the namespaced partial
  def to_partial_path
    "operator/feed_items/feed_item"
  end

  # Real-time Turbo Streams - broadcast new feed items to all connected users
  after_create_commit :broadcast_to_feed

  def broadcast_to_feed
    return if type.in?(%w[new-user daily-digest])

    ActsAsTenant.with_tenant(operator) do
      broadcast_prepend_to [operator, "feed_items"], target: "feed-items", partial: "operator/feed_items/feed_item", locals: { feed_item: self, comments: false }
    end
  rescue => e
    Rails.logger.warn("FeedItem broadcast failed: #{e.class}: #{e.message}")
  end

  has_rich_text :text

  validate :photo_files_accepted

  acts_as_tenant :operator

  scope :for_operator, ->(operator) { where(operator: operator) }
  scope :for_week, -> (week_start, week_end) { where('feed_items.created_at > ? and feed_items.created_at <= ?', week_start, week_end) }
  scope :expenses, -> { where(expense: true) }

  # Types of feed_items
  scope :member_feedbacks, -> { where("blob->> 'type' = ?", "feedback") }
  scope :childcare_reservations, -> { where("blob->> 'type' = ?", "childcare-reservation") }
  scope :day_passes, -> { where("blob->> 'type' = ?", "day-pass") }
  scope :reservations, -> { where("blob->> 'type' = ?", "reservation") }
  scope :announcements, -> { where("blob->> 'type' = ?", "announcement") }
  scope :questions, -> { where("blob->> 'text' LIKE '%\?%'") }
  scope :activity, -> { where("blob->> 'type' IN (?, ?, ?, ?, ?, ?)", "feedback", "day-pass", "reservation", "subscription", "checkin", "paid-room-reservation") }
  scope :notes, -> { where("blob->> 'type' = ? AND expense = ?", "post", false) }
  scope :financial, -> { where("blob->> 'type' IN (?) OR expense = ?", "refund", true) }
  scope :expenses, -> { where(expense: true) }
  scope :unanswered, -> { left_outer_joins(:feed_item_comments).where('feed_item_comments.id IS NULL') }
  scope :answered, -> { left_outer_joins(:feed_item_comments).where('feed_item_comments.id IS NOT NULL') }

  def search_data
    {
      text: text.to_plain_text,
      type: type,
      amount: amount,
      user_name: user.present? ? user.name : "Anonymous",
      comments: feed_item_comments.map(&:comment),
      stripe_customer_id: user.present? ? user.stripe_customer_id_for_location(location) : nil, # TODO: search may break here
      operator_id: operator_id,
    }
  end

  def action_text
    case type
    when "announcement"
      "posted an announcement"
    when "childcare-reservation"
      "made a childcare reservation"
    when "reservation"
      "reserved a room"
    when "paid-room-reservation"
      "booked a paid meeting room"
    when "feedback"
      "sent a message"
    when "refund"
      "was issued a refund"
    when "subscription"
      "became a member"
    when "day-pass"
      "bought a day pass"
    when "post"
      if expense?
        "posted an expense"
      else
        "posted a mgmt note"
      end
    when "checkin"
      "checked in"
    when "membership_cancellation"
      "canceled their membership"
    when "membership_updated"
      "updated their membership"
    when "account_deletion"
      "deleted their account"
    when "new-user"
      "signed up"
    when "weekly-update"
      "Your weekly update has been posted"
    when "payment_failed"
      "had a payment failure"
    when "lease_renewal"
      "has a lease renewal proposal"
    when "membership_paused"
      "paused their membership"
    when "membership_unpaused"
      "resumed their membership"
    when "demand-miss"
      "couldn't find an available room"
    when "event-proposed"
      "proposed an event"
    when "daily-digest"
      "Daily activity summary"
    end
  end

  def requires_approval?
    ["subscription", "day-pass", "day-pass-bundle", "new-user", "reservation", "paid-room-reservation"].any? {|t| type == t}
  end

  def weekly_update?
    type == "weekly-update"
  end

  def type
    blob["type"]
  end

  def amount
    blob["amount"]
  end

  def has_photos?
    photos.count > 0
  end

  def feed_photos
    photos.map do |photo|
      photo.variant(auto_orient: true)
    end
  end

  def thumbnails
    photos.map do |photo|
      photo.variant(resize: "180x180", auto_orient: true)
    end
  end

  # Auto-classify a post as an expense ONLY when both signals are present:
  # an expense keyword AND a dollar amount. "We spent the afternoon
  # rearranging the lobby" should stay a regular note; "Spent $5 on
  # coffee" should book itself as an expense.
  def is_expense_feed?
    return false unless text.present?
    plain = text.to_plain_text.downcase
    plain.include_any?(["spent", "expense", "expenditure"]) && plain.match?(/\$\d/)
  end

  # Mobile posts come in as plain text (literal `\n` newlines, no tags) and
  # need `white-space: pre-wrap` to render line breaks. Web/Trix posts come
  # in as structured HTML (lists, paragraphs, divs) where `pre-wrap` makes
  # the whitespace BETWEEN tags visible as enormous gaps. Skip pre-wrap
  # whenever the body has any HTML tag.
  def rich_html_body?
    return false if text.blank?
    text.body.to_html.match?(/<[a-z]/i)
  end

  def parse_amount
    if text.present?
      raw = text.to_plain_text.scan(/\$\d+.*\d+/).first
      if raw.present?
        amount = (raw.tr!("$", "").to_f * 100).to_i
        blob["amount"] = amount
      end
    end
  end

  def set_expense
    self.expense = true
  end

  def unset_expense
    self.expense = false
  end

  # Lazy relationships

  def announcement
    blob_relation("announcement_id", Announcement.unscoped)
  end

  def childcare_reservation
    blob_relation("childcare_reservation_id", ChildcareReservation.unscoped)
  end

  def reservation
    blob_relation("reservation_id", Reservation.unscoped)
  end

  def member_feedback
    blob_relation("member_feedback_id", MemberFeedback.unscoped)
  end

  def day_pass
    blob_relation("day_pass_id", DayPass.unscoped)
  end

  def day_pass_bundle
    blob_relation("day_pass_bundle_id", DayPassBundle.unscoped)
  end

  def subscription
    blob_relation("subscription_id", Subscription)
  end

  def checkin
    blob_relation("checkin_id", Checkin)
  end

  def weekly_update
    blob_relation("weekly_update_id", WeeklyUpdate)
  end

  def invoice
    invoice_id = blob["invoice_id"]

    Invoice.find_by(id: invoice_id)
  end

  private

  VALID_ATTACHMENT_REGEX = /image\/(jpeg|jpg|png|gif)/

  def photo_files_accepted
    if photos.any? { |photo| !photo.content_type.match VALID_ATTACHMENT_REGEX }
      errors.add(:photos, "must be of file type .jpeg, .jpg, .png, or .gif")
    end
  end

  def blob_relation(key, klass)
    rel_id = blob[key]
    if rel_id.nil?
      nil
    else
      klass.find(rel_id)
    end
  end
end
