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
  belongs_to :member_feedback
  belongs_to :user
  belongs_to :operator

  acts_as_tenant :operator

  validates :body, presence: true

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
end
