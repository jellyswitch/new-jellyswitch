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
#  location_id :bigint(8)
#  operator_id :integer          not null
#  user_id     :integer
#
# Indexes
#
#  index_member_feedbacks_on_location_id  (location_id)
#
# Foreign Keys
#
#  fk_rails_...  (location_id => locations.id)
#

class MemberFeedback < ApplicationRecord
  belongs_to :operator
  belongs_to :user

  acts_as_scopable :operator, :location

  scope :recent, ->() { where('created_at > ?', Time.now - 7.days) }

  def anonymous?
    self.anonymous == true
  end
end
