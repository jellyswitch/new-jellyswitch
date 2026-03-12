
# == Schema Information
#
# Table name: member_feedbacks
#
#  id          :bigint(8)        not null, primary key
#  anonymous   :boolean          default(FALSE), not null
#  comment     :text
#  rating      :integer
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  operator_id :integer          not null
#  location_id :integer
#  user_id     :integer
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

  def unread_reply_count
    return 0 if feedback_replies.empty?
    return feedback_replies.count if last_read_at.nil?
    feedback_replies.where("created_at > ?", last_read_at).count
  end
end
