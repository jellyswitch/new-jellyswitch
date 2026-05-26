# == Schema Information
#
# Table name: room_demand_misses
#
#  id          :bigint(8)        not null, primary key
#  day_of_week :integer
#  hour_of_day :integer
#  missed_at   :datetime         not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  location_id :bigint(8)        not null
#  operator_id :bigint(8)        not null
#  user_id     :bigint(8)        not null
#
# Indexes
#
#  idx_demand_misses_heatmap                              (location_id,day_of_week,hour_of_day)
#  index_room_demand_misses_on_location_id                (location_id)
#  index_room_demand_misses_on_location_id_and_missed_at  (location_id,missed_at)
#  index_room_demand_misses_on_operator_id                (operator_id)
#  index_room_demand_misses_on_user_id                    (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (location_id => locations.id)
#  fk_rails_...  (operator_id => operators.id)
#  fk_rails_...  (user_id => users.id)
#
class RoomDemandMiss < ApplicationRecord
  belongs_to :user
  belongs_to :operator
  belongs_to :location

  scope :for_location, ->(location) { where(location: location) }
  scope :for_week, ->(start_date, end_date) { where(missed_at: start_date..end_date) }
  scope :last_30_days, -> { where("missed_at >= ?", 30.days.ago) }

  def self.heatmap_data(location, start_date: 30.days.ago, end_date: Time.current)
    for_location(location)
      .where(missed_at: start_date..end_date)
      .group(:day_of_week, :hour_of_day)
      .count
  end

  def self.peak_times(location, limit: 5)
    heatmap_data(location)
      .sort_by { |_, count| -count }
      .first(limit)
  end

  def self.estimated_missed_revenue(location, start_date: 30.days.ago)
    miss_count = for_location(location).where("missed_at >= ?", start_date).count
    avg_rate = location.rooms.visible.average(:hourly_rate_in_cents) || 0
    avg_duration = 60 # assume 1 hour average
    (miss_count * avg_rate * avg_duration / 60.0 / 100.0).round(2)
  end
end
