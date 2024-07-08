class Amenity < ApplicationRecord
  belongs_to :room
  has_and_belongs_to_many :reservations

  validates :name, presence: true
  validates :price, numericality: { greater_than_or_equal_to: 0 }

  def price=(value)
    super(value.present? ? value : 0)
  end
end
