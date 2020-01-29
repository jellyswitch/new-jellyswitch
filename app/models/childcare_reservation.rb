# == Schema Information
#
# Table name: childcare_reservations
#
#  id                :bigint(8)        not null, primary key
#  cancelled         :boolean          default(FALSE), not null
#  date              :date             not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  child_profile_id  :integer          not null
#  childcare_slot_id :integer          not null
#

class ChildcareReservation < ApplicationRecord
  belongs_to :childcare_slot
  belongs_to :child_profile

  default_scope { where(cancelled: false) }
  scope :upcoming, -> { where("date >= ?", Time.zone.now) }
end
