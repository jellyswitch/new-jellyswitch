class Subscription < ApplicationRecord
  # Relationships
  belongs_to :user
  belongs_to :plan

  # Scopes
  scope :active, ->() { where(active: true) }
end
