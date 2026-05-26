# == Schema Information
#
# Table name: office_leases
#
#  id                           :bigint(8)        not null, primary key
#  always_allow_building_access :boolean          default(TRUE), not null
#  auto_renew                   :boolean          default(FALSE), not null
#  deposit_amount_in_cents      :integer          default(0), not null
#  end_date                     :date             not null
#  escalation_type              :string
#  escalation_value             :decimal(10, 2)
#  initial_invoice_date         :date
#  renewal_notice_days          :integer          default(60), not null
#  start_date                   :date             not null
#  created_at                   :datetime         not null
#  updated_at                   :datetime         not null
#  cpi_index_series_id          :string
#  location_id                  :bigint(8)
#  office_id                    :bigint(8)
#  operator_id                  :bigint(8)
#  organization_id              :bigint(8)
#  subscription_id              :bigint(8)
#  user_id                      :bigint(8)
#
# Indexes
#
#  index_office_leases_on_location_id      (location_id)
#  index_office_leases_on_office_id        (office_id)
#  index_office_leases_on_operator_id      (operator_id)
#  index_office_leases_on_organization_id  (organization_id)
#  index_office_leases_on_subscription_id  (subscription_id)
#  index_office_leases_on_user_id          (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (location_id => locations.id) ON DELETE => nullify
#  fk_rails_...  (office_id => offices.id) ON DELETE => nullify
#  fk_rails_...  (operator_id => operators.id) ON DELETE => nullify
#  fk_rails_...  (organization_id => organizations.id) ON DELETE => nullify
#  fk_rails_...  (subscription_id => subscriptions.id) ON DELETE => nullify
#  fk_rails_...  (user_id => users.id)
#
FactoryBot.define do
  factory :office_lease do
    association :organization
    association :office
    association :subscription

    start_date { 6.months.ago.to_date }
    end_date { 6.months.from_now.to_date }

    initial_invoice_date { 6.months.ago.to_date }
    always_allow_building_access { true }

    operator { Operator.find_by(name: "Cowork Tahoe") || association(:operator) }
    location { Location.find_by(name: "Cowork Tahoe") || association(:location) }
  end
end
