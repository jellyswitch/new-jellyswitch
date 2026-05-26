
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

  scope :recent, ->() { where('created_at > ?', Time.now - 7.days) }

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
end
