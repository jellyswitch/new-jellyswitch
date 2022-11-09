class Operator::PlanCategoriesController < Operator::BaseController
  include PlansHelper
  before_action :background_image

  def index
    find_plan_categories
  end

  private

  def find_plan_categories
    @plan_categories = current_tenant.plan_categories.select do |plan_category|
      plan_category.plans.visible.available.for_location(current_location).count.positive?
    end
  end
end