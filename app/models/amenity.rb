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

  # An amenity's behavior is derived from its rates, not a stored type
  # (see docs/adr/0007-amenity-behavior-derived-from-rate.md):
  #   both rates 0  -> a passive room feature (informational, never charged)
  #   any rate > 0  -> an orderable add-on (selectable per reservation, charged)
  scope :add_ons, -> { where("price > 0 OR membership_price > 0") }
  scope :features, -> { where(price: 0, membership_price: 0) }

  def orderable?
    [price.to_f, membership_price.to_f].max > 0
  end

  def feature?
    !orderable?
  end

  def price=(value)
    super(value.present? ? value : 0)
  end

  def membership_price=(value)
    super(value.present? ? value : 0)
  end
end
