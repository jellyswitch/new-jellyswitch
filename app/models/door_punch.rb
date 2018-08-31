class DoorPunch < ApplicationRecord
  # Relationships
  belongs_to :door
  belongs_to :user

  # View helpers
  def pretty_datetime
    created_at.strftime("%m/%d/%Y at %l:%M%P")
  end
end
