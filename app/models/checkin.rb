# == Schema Information
#
# Table name: checkins
#
#  id           :bigint(8)        not null, primary key
#  datetime_in  :datetime         not null
#  datetime_out :datetime
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  invoice_id   :integer
#  location_id  :integer          not null
#  user_id      :integer          not null
#

class Checkin < ApplicationRecord
  belongs_to :invoice, optional: true
  belongs_to :location
  belongs_to :user

  scope :open, -> { where(datetime_out: nil) }
  scope :for_location, -> (loc) { where(location_id: loc.id) }

  def charge_description
    "Hourly charge for #{location.name}"
  end
end
