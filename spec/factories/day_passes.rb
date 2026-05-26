# == Schema Information
#
# Table name: day_passes
#
#  id               :bigint(8)        not null, primary key
#  billable_type    :string
#  complimentary    :boolean          default(FALSE), not null
#  day              :date             not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  billable_id      :bigint(8)
#  day_pass_type_id :integer
#  invoice_id       :integer
#  location_id      :integer
#  operator_id      :integer          default(1), not null
#  stripe_charge_id :string
#  user_id          :integer          not null
#
# Indexes
#
#  index_day_passes_on_billable_type_and_billable_id  (billable_type,billable_id)
#  index_day_passes_on_location_id                    (location_id)
#  index_day_passes_on_operator_id                    (operator_id)
#
FactoryBot.define do
  factory :day_pass do
    day { Date.current }
    operator { Operator.find_by(name: "Cowork Tahoe") || association(:operator) }
    location { Location.find_by(name: "Cowork Tahoe") }
    user { association(:user) }
    day_pass_type { association(:day_pass_type) }
    billable { association(:user) }
  end
end
