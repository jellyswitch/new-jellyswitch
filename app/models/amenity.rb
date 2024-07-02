class Amenity < ApplicationRecord
  belongs_to :room

  validates :name, presence: true
  validates :price, presence: true, numericality: { greater_than_or_equal_to: 0 }
end
