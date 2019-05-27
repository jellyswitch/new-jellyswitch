# == Schema Information
#
# Table name: checkins
#
#  id            :bigint(8)        not null, primary key
#  billable_type :string
#  datetime_in   :datetime         not null
#  datetime_out  :datetime
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  billable_id   :bigint(8)
#  invoice_id    :integer
#  location_id   :integer          not null
#  user_id       :integer          not null
#
# Indexes
#
#  index_checkins_on_billable_type_and_billable_id  (billable_type,billable_id)
#

class Checkin < ApplicationRecord
  belongs_to :billable, polymorphic: true
  belongs_to :invoice, optional: true
  belongs_to :location
  belongs_to :user

  scope :open, -> { where(datetime_out: nil) }
  scope :for_location, -> (loc) { where(location_id: loc.id) }
  scope :for_operator, -> (op) { where(location_id: [op.locations.map(&:id)]) }
  scope :this_month, -> () { where("datetime_in > ?", Time.current.beginning_of_month) }

  def charge_description
    "Hourly charge for #{location.name}"
  end

  def charge_amount
    (per_minute_charge_amount * minutes).to_i
  end

  def per_minute_charge_amount
    location.hourly_rate_in_cents.to_f / 60.0
  end

  def per_hour_charge_amount
    location.hourly_rate_in_cents
  end

  def seconds
    (datetime_out - datetime_in).to_i
  end

  def minutes
    (seconds.to_f / 1.minute).ceil
  end

  def hours
    (seconds.to_f / 1.hour).ceil
  end

  def open?
    datetime_out.blank?
  end
end
