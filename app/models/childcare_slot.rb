# == Schema Information
#
# Table name: childcare_slots
#
#  id          :bigint(8)        not null, primary key
#  deleted     :boolean
#  name        :string
#  week_day    :integer
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  location_id :integer
#

class ChildcareSlot < ApplicationRecord
  belongs_to :location
  has_many :childcare_reservations

  scope :visible, -> { where(deleted: false) }

  def visible?
    deleted == false
  end

  def weekday_name
    Date::DAYNAMES[week_day]
  end

  def pretty_name
    "#{weekday_name} #{name}"
  end
end
