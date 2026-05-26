# == Schema Information
#
# Table name: beacons
#
#  id           :bigint(8)        not null, primary key
#  available    :boolean          default(TRUE), not null
#  battery_pct  :integer
#  installed_at :datetime
#  last_seen_at :datetime
#  major        :integer          not null
#  minor        :integer          not null
#  name         :string           not null
#  notes        :text
#  uuid         :string           not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  door_id      :bigint(8)
#  location_id  :bigint(8)        not null
#  operator_id  :integer          default(1), not null
#
# Indexes
#
#  index_beacons_on_door_id                    (door_id)
#  index_beacons_on_location_id                (location_id)
#  index_beacons_on_operator_id                (operator_id)
#  index_beacons_on_operator_uuid_major_minor  (operator_id,uuid,major,minor) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (door_id => doors.id)
#  fk_rails_...  (location_id => locations.id)
#
class Beacon < ApplicationRecord
  belongs_to :operator
  belongs_to :location
  belongs_to :door, optional: true

  acts_as_scopable :operator, :location

  validates :name,    presence: true
  validates :uuid,    presence: true
  validates :major,   presence: true, numericality: { only_integer: true, in: 0..65_535 }
  validates :minor,   presence: true, numericality: { only_integer: true, in: 0..65_535 }
  validates :battery_pct, numericality: { only_integer: true, in: 0..100 }, allow_nil: true
  validates :uuid, uniqueness: { scope: [:operator_id, :major, :minor] }

  scope :available,   -> { where(available: true) }
  scope :unavailable, -> { where(available: false) }

  def low_battery?
    battery_pct.present? && battery_pct <= 20
  end

  def stale?
    last_seen_at.nil? || last_seen_at < 24.hours.ago
  end
end
