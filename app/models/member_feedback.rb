
# == Schema Information
#
# Table name: member_feedbacks
#
#  id           :bigint(8)        not null, primary key
#  anonymous    :boolean          default(FALSE), not null
#  comment      :text
#  last_read_at :datetime
#  rating       :integer
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  location_id  :integer
#  operator_id  :integer          not null
#  user_id      :integer
#
# Indexes
#
#  index_member_feedbacks_on_location_id  (location_id)
#

class MemberFeedback < ApplicationRecord
  include HasLocation

  belongs_to :operator
  belongs_to :user
  has_many :feedback_replies, dependent: :destroy

  acts_as_tenant :operator

  ARCHIVED_AUTHOR_MESSAGE =
    "This account is no longer active. Please contact the space directly.".freeze

  # Archiving is the admin's "deactivate" gesture, but the API deliberately
  # keeps archived users able to LOG IN (cross-tenant reasons — see
  # Api::V1::AuthController#login). Nothing stopped them from messaging, so
  # archiving someone who was flooding the inbox changed nothing (LaTasha,
  # Untethered, 2026-08). New threads and replies now refuse an archived
  # author at the model layer, which covers every entry path — interactors,
  # the API's bare-save fallback, and web — while staff replying INTO an
  # archived member's old thread is untouched (the author there is staff).
  validate :author_not_archived, on: :create

  scope :recent, ->() { where('created_at > ?', Time.now - 7.days) }

  # Not hidden from the admin conversations inbox.
  scope :not_dismissed, -> { where(dismissed_at: nil) }

  # Conversations the member actually engaged in — i.e. they sent at least one
  # message. That's either a non-blank original comment (member-initiated) or a
  # reply authored by the thread owner (the member). This deliberately excludes
  # host-greeting-only threads (comment is nil and only the host has replied),
  # which EnsureHostGreeting creates for every visitor.
  scope :with_member_message, -> {
    where(
      "(member_feedbacks.comment IS NOT NULL AND member_feedbacks.comment <> '') " \
      "OR EXISTS (SELECT 1 FROM feedback_replies fr " \
      "WHERE fr.member_feedback_id = member_feedbacks.id " \
      "AND fr.user_id = member_feedbacks.user_id)"
    )
  }

  def anonymous?
    self.anonymous == true
  end

  def has_unread_replies?
    return false if feedback_replies.empty?
    return true if last_read_at.nil?
    feedback_replies.where("created_at > ?", last_read_at).exists?
  end

  def mark_as_read!
    update_column(:last_read_at, Time.current)
  end

  # Hide the thread from the admin inbox. A later reply from either side
  # resurfaces it (see FeedbackReply#resurface_dismissed_thread).
  def dismiss!
    update_column(:dismissed_at, Time.current)
  end

  # Undo a dismiss: put the thread straight back in the admin inbox.
  def restore!
    update_column(:dismissed_at, nil)
  end

  # How long after the last reply on either side the conversation is treated
  # as "wrapped up" — at which point the rate-this-experience CTA becomes
  # available. Showing the rating immediately after the first staff reply
  # felt premature; 24h gives both sides a chance to follow up first.
  RATING_WRAP_UP_WINDOW = 24.hours

  # Returns true when the member should be invited to rate this thread.
  # Rules:
  # - Already rated → false (no second prompt)
  # - No staff reply yet → false (nothing to rate)
  # - Last activity on either side <24h ago → false (still active)
  #
  # `feedback_replies` is loaded into memory once and reused so the call
  # is a single SQL round-trip even when the replies aren't pre-loaded
  # (controller serializers tend to enumerate them too).
  def can_rate?
    return false if rating.present?
    replies = feedback_replies.to_a
    return false unless replies.any?(&:from_admin?)
    last_reply_at = replies.map(&:created_at).max
    last_reply_at < RATING_WRAP_UP_WINDOW.ago
  end

  def unread_reply_count
    return 0 if feedback_replies.empty?
    return feedback_replies.count if last_read_at.nil?
    feedback_replies.where("created_at > ?", last_read_at).count
  end

  private

  def author_not_archived
    errors.add(:base, ARCHIVED_AUTHOR_MESSAGE) if user&.archived?
  end
end
