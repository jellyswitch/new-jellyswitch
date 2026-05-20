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
