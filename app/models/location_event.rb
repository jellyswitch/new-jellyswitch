# == Schema Information
#
# Table name: location_events
#
#  id          :bigint(8)        not null, primary key
#  date        :date             not null
#  name        :string           not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  location_id :bigint(8)
#  operator_id :bigint(8)        not null
#
# Indexes
#
#  index_location_events_on_location_id  (location_id)
#  index_location_events_on_operator_id  (operator_id)
#
class LocationEvent < ApplicationRecord
  belongs_to :operator
  belongs_to :location, optional: true

  acts_as_tenant :operator

  validates :name, presence: true
  validates :date, presence: true

  scope :for_location, ->(location) { where(location: location) }
  scope :in_range, ->(from, to) { where(date: from..to) }

  def self.chart_annotations(location, from, to)
    for_location(location).in_range(from, to).map do |event|
      { date: event.date.to_s, label: event.name }
    end
  end
end
