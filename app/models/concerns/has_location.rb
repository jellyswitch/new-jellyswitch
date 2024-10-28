module HasLocation
  # We do this instead of acts_as_scopable because we need to retain items without location_id (legacy data)

  extend ActiveSupport::Concern

  included do
    belongs_to :location, optional: true

    # items from the location or items that are not associated with any location (legacy data)
    scope :for_location, ->(location) { where("location_id = ? OR location_id IS NULL", location&.id) }
  end
end