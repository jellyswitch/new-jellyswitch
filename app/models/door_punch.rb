# == Schema Information
#
# Table name: door_punches
#
#  id          :bigint(8)        not null, primary key
#  door_id     :integer
#  user_id     :integer
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  operator_id :integer          default(1), not null
#

class DoorPunch < ApplicationRecord
  # Relationships
  belongs_to :door
  belongs_to :user
  belongs_to :operator
  acts_as_tenant :operator

  # View helpers
  def pretty_datetime
    created_at.strftime("%m/%d/%Y at %l:%M%P")
  end
end
