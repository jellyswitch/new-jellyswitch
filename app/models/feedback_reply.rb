# == Schema Information
#
# Table name: feedback_replies
#
#  id                 :bigint(8)        not null, primary key
#  body               :text             not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  member_feedback_id :bigint(8)        not null
#  operator_id        :integer          not null
#  user_id            :bigint(8)        not null
#
# Indexes
#
#  index_feedback_replies_on_member_feedback_id  (member_feedback_id)
#  index_feedback_replies_on_operator_id         (operator_id)
#  index_feedback_replies_on_user_id             (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (member_feedback_id => member_feedbacks.id)
#  fk_rails_...  (user_id => users.id)
#
class FeedbackReply < ApplicationRecord
  # touch: true bumps the parent thread's updated_at on every reply, no matter
  # which path created it (member API, admin API, web, or the SaveReply
  # interactor). The admin and member inboxes sort threads by updated_at so the
  # most recently active conversation floats to the top — without this, threads
  # sorted by their greeting-shell created_at and active chats sank out of view.
  belongs_to :member_feedback, touch: true
  belongs_to :user
  belongs_to :operator

  acts_as_tenant :operator

  validates :body, presence: true

  # Restarting a conversation (a new reply from either side) brings it back to
  # the admin inbox if it had been dismissed. touch: true already bumps the
  # thread's updated_at so it floats to the top.
  after_create :resurface_dismissed_thread

  delegate :location, to: :member_feedback

  # "From staff" = anyone other than the member who originated the thread.
  # The MemberFeedbackPolicy lets any admin/general-manager/community-manager
  # reply regardless of location_managements, so requiring
  # admin_or_manager?(location) here was too strict — it silently filtered
  # out replies from operator-wide admins (e.g. multi-location admins not
  # assigned to this specific location) and broke the unread-reply nudge.
  # The simpler check matches the user-facing semantics: anyone who isn't
  # the requester is "staff" in the conversation.
  def from_admin?
    user_id != member_feedback.user_id
  end

  private

  def resurface_dismissed_thread
    return if member_feedback.nil? || member_feedback.dismissed_at.nil?
    member_feedback.update_columns(dismissed_at: nil)
  end
end
