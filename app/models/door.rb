class Door < ApplicationRecord
  # Slugs
  extend FriendlyId
  friendly_id :name, use: :slugged

  # Relationships
  has_many :door_punches
  belongs_to :operator
  acts_as_tenant :operator
end
