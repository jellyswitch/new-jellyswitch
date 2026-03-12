class FeedbackReply < ApplicationRecord
  belongs_to :member_feedback
  belongs_to :user
  belongs_to :operator

  acts_as_tenant :operator

  validates :body, presence: true

  delegate :location, to: :member_feedback

  def from_admin?
    user.admin_or_manager?(member_feedback.location)
  end
end
