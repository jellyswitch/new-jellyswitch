# == Schema Information
#
# Table name: plan_categories
#
#  id          :bigint(8)        not null, primary key
#  name        :string
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  operator_id :integer
#
class PlanCategory < ApplicationRecord
  has_many :plans
end
