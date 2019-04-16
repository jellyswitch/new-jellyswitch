# == Schema Information
#
# Table name: day_pass_types
#
#  id              :bigint(8)        not null, primary key
#  amount_in_cents :integer          default(0), not null
#  available       :boolean          default(TRUE), not null
#  name            :string           not null
#  visible         :boolean          default(TRUE), not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  operator_id     :integer          not null
#

class DayPassType < ApplicationRecord
  has_many :day_passes
  belongs_to :operator
  acts_as_tenant :operator

  # Scopes
  scope :available, -> { where(available: true) }
  scope :visible, -> { where(visible: true) }

  def self.options_for_select(operator)
    where(operator_id: operator.id).available.visible
  end

  def self.all_options_for_select(operator)
    where(operator_id: operator.id).available
  end
end
