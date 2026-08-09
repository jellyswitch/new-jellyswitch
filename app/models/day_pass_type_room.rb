# == Schema Information
#
# Table name: day_pass_type_rooms
#
#  id               :bigint(8)        not null, primary key
#  position         :integer          not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  day_pass_type_id :bigint(8)        not null
#  room_id          :bigint(8)        not null
#
# Indexes
#
#  index_day_pass_type_rooms_on_room_id  (room_id)
#  index_dpt_rooms_on_type_and_position  (day_pass_type_id,position)
#  index_dpt_rooms_on_type_and_room      (day_pass_type_id,room_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (day_pass_type_id => day_pass_types.id)
#  fk_rails_...  (room_id => rooms.id)
#
# One row = one room in a Day Office type's pool; position is the admin's
# fill order (1 = first choice). See ADR 0026.
class DayPassTypeRoom < ApplicationRecord
  belongs_to :day_pass_type
  belongs_to :room

  validates :position, numericality: { only_integer: true, greater_than: 0 }
  validates :room_id, uniqueness: { scope: :day_pass_type_id }
  validate :room_matches_type_location

  private

  def room_matches_type_location
    return if room.nil? || day_pass_type.nil?
    return if room.location_id == day_pass_type.location_id
    errors.add(:room, "must belong to the same location as the day pass type")
  end
end
