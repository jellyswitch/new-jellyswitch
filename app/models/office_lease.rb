# == Schema Information
#
# Table name: office_leases
#
#  id              :bigint(8)        not null, primary key
#  end_date        :date             not null
#  start_date      :date             not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  office_id       :bigint(8)        not null
#  operator_id     :bigint(8)        not null
#  organization_id :bigint(8)        not null
#  plan_id         :bigint(8)        not null
#
# Indexes
#
#  index_office_leases_on_office_id        (office_id)
#  index_office_leases_on_operator_id      (operator_id)
#  index_office_leases_on_organization_id  (organization_id)
#  index_office_leases_on_plan_id          (plan_id)
#
# Foreign Keys
#
#  fk_rails_...  (office_id => offices.id)
#  fk_rails_...  (operator_id => operators.id)
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (plan_id => plans.id)
#

class OfficeLease < ApplicationRecord
  belongs_to :operator
  belongs_to :organization
  belongs_to :office

  has_one_attached :lease_agreement
end
