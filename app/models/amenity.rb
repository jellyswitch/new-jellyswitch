# == Schema Information
#
# Table name: amenities
#
#  id               :bigint(8)        not null, primary key
#  membership_price :float            default(0.0)
#  name             :string
#  price            :float            default(0.0)
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  room_id          :bigint(8)        not null
#
# Indexes
#
#  index_amenities_on_room_id  (room_id)
#
# Foreign Keys
#
#  fk_rails_...  (room_id => rooms.id)
#
class Amenity < ApplicationRecord
  belongs_to :room
  has_and_belongs_to_many :reservations

  validates :name, presence: true
  validates :price, numericality: { greater_than_or_equal_to: 0 }
  validates :membership_price, numericality: { greater_than_or_equal_to: 0 }

  AV_EQUIPMENT = "AV Equipment".freeze
  WHITEBOARD = "Whiteboard".freeze

  def price=(value)
    super(value.present? ? value : 0)
  end

  def membership_price=(value)
    super(value.present? ? value : 0)
  end
end
