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
