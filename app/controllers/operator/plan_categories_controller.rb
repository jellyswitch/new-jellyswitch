class Operator::PlanCategoriesController < Operator::BaseController
  include PlansHelper
  before_action :require_authentication
  before_action :background_image

  def index
    find_plan_categories
  end

  private

  def find_plan_categories
    @plan_categories = current_location.plan_categories.select do |plan_category|
      plan_category.plans.individual.visible.available.for_location(current_location).count.positive?
    end

    @uncategorized_plans = current_location.plans.uncategorized.individual.available.visible
  end
end