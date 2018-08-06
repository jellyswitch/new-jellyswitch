class Plan < ApplicationRecord
    # Slugs
    extend FriendlyId
    friendly_id :name, use: :slugged

    INTERVAL_OPTIONS = [
      "once",
      "hourly",
      "daily",
      "monthly",
      "annually"
    ]

    scope :available, ->() { where(available: true) }
    scope :visible, ->() { where(visible: true) }
    
    def self.options_for_interval
      INTERVAL_OPTIONS
    end
end
