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
#  stripe_sku_id   :string
#

class DayPassType < ApplicationRecord
  belongs_to :operator
  acts_as_tenant :operator
end
