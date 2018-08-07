class Subscription < ApplicationRecord
  # Relationships
  belongs_to :user
  belongs_to :plan

  # Scopes
  scope :active, ->() { where(active: true) }

  def pretty_datetime
    updated_at.strftime("%m/%d/%Y at %l:%M%P")
  end
end
