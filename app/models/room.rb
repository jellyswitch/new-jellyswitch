class Room < ApplicationRecord
  # Relationships
  has_many :reservations

  # Slugs
  extend FriendlyId
  friendly_id :name, use: :slugged

  def self.options_for_select
    Room.all.map do |room|
      [room.name, room.id]
    end
  end
end
