class FeedItem < ApplicationRecord
  # Relationships
  belongs_to :operator
  belongs_to :user

  acts_as_tenant :operator

  scope :for_operator, ->(operator) { where(operator_id: operator.id) }
end
