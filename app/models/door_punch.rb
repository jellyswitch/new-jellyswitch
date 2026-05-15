
# == Schema Information
#
# Table name: door_punches
#
#  id          :bigint(8)        not null, primary key
#  json        :jsonb
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  door_id     :integer
#  operator_id :integer          default(1), not null
#  user_id     :integer
#
# Indexes
#
#  index_door_punches_on_operator_id  (operator_id)
#

class DoorPunch < ApplicationRecord
  # Relationships
  belongs_to :door
  belongs_to :user
  belongs_to :operator
  acts_as_tenant :operator

  scope :this_month, -> () { where("created_at > ?", Time.current.beginning_of_month ) }

  after_create :log_activity

  # View helpers
  def pretty_datetime
    created_at.strftime("%m/%d/%Y at %l:%M%P")
  end

  def log_activity
    Activity.log(user: user, kind: :door_punch, subject: self, operator: operator)
  end

  def to_activity_payload
    {
      "door_name" => door&.name,
    }
  end
end
