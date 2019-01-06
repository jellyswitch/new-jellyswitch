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
