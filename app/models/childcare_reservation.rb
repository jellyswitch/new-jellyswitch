class ChildcareReservation < ApplicationRecord
  belongs_to :childcare_slot
  belongs_to :child_profile

  scope :upcoming, -> { where("date >= ?", Time.zone.now) }
end
