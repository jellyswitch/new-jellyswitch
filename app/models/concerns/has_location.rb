module HasLocation
  # We do this instead of acts_as_scopable because we need to retain items without location_id (legacy data)

  extend ActiveSupport::Concern

  included do
    belongs_to :location, optional: true

    # items from the location or items that are not associated with any location (legacy data)
    # Hash form so the column is qualified with this model's table — the old
    # raw-SQL version raised PG::AmbiguousColumn as soon as the relation was
    # joined to another table that also has a location_id (e.g.
    # day_passes.for_location(...).joins(:day_pass_type)).
    scope :for_location, ->(location) { where(location_id: [location&.id, nil]) }
  end
end