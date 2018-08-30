class Door < ApplicationRecord
  # Slugs
  extend FriendlyId
  friendly_id :name, use: :slugged
end
