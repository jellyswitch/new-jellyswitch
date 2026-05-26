# == Schema Information
#
# Table name: plan_categories
#
#  id          :bigint(8)        not null, primary key
#  name        :string
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  location_id :integer
#  operator_id :integer
#
# Indexes
#
#  index_plan_categories_on_location_id  (location_id)
#
require "test_helper"

class PlanCategoryTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
