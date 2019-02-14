# == Schema Information
#
# Table name: day_passes
#
#  id               :bigint(8)        not null, primary key
#  day              :date             not null
#  user_id          :integer          not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  stripe_charge_id :string
#  operator_id      :integer          default(1), not null
#

class DayPass < ApplicationRecord
  # Relationships
  belongs_to :user
  belongs_to :operator
  acts_as_tenant :operator

  # Scopes
  scope :today, ->() { where(day: Time.current) }
  scope :fulfilled, ->() { where('stripe_charge_id IS NOT NULL') }

  # Instance methods
  def pretty_day
    day.strftime("%m/%d/%Y")
  end

  def fulfilled?
    stripe_charge_id.present?
  end

  def charge_description
    "#{operator.name} Day Pass for #{pretty_day}"
  end

  def stripe_charge
    Stripe::Charge.retrieve(self.stripe_charge_id)
  end
end
