# == Schema Information
#
# Table name: day_pass_types
#
#  id                           :bigint(8)        not null, primary key
#  always_allow_building_access :boolean          default(FALSE), not null
#  amount_in_cents              :integer          default(0), not null
#  available                    :boolean          default(TRUE), not null
#  code                         :string
#  name                         :string           not null
#  visible                      :boolean          default(TRUE), not null
#  created_at                   :datetime         not null
#  updated_at                   :datetime         not null
#  operator_id                  :integer          not null
#  location_id                  :integer
#

class DayPassType < ApplicationRecord
  include HasLocation

  has_many :day_passes
  belongs_to :operator
  acts_as_tenant :operator

  has_rich_text :description

  # Scopes
  scope :available, -> { where(available: true) }
  scope :visible, -> { where(visible: true) }
  scope :invisible, -> { where(visible: false) }
  scope :free, -> { where(amount_in_cents: 0) }
  scope :for_operator, ->(operator) { where(operator_id: operator.id) }
  scope :for_code, ->(code) { where(code: code) }
  scope :cheapest, -> { order("amount_in_cents ASC").first }

  def self.options_for_select(operator)
    where(operator_id: operator.id).available.visible
  end

  def self.all_options_for_select(location, user)
    if user.has_billing_for_location?(location) || user.out_of_band?
      where(location_id: location.id).available
    else
      where(location_id: location.id).available.free
    end
  end

  def free?
    amount_in_cents == 0
  end

  # Meeting room limit helpers
  def has_meeting_room_limit?
    included_meeting_room_minutes.present?
  end

  def overage_rate_per_minute_in_cents
    overage_rate_in_cents / 60.0
  end
end
