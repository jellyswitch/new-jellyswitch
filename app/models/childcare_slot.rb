class ChildcareSlot < ApplicationRecord
  belongs_to :location

  scope :visible, -> { where(deleted: false) }
end
