class Operator::Admin::PlanCategoriesController < Operator::BaseController
  include PlansHelper
  before_action :background_image

  # TODO: policies

  def index
    find_plan_categories
  end

  def new
    @plan_category = PlanCategory.new
  end

  def create
    @plan_category = PlanCategory.new(plan_category_params)
    
    if @plan_category.save
      flash[:notice] = "Plan Category created."
      turbo_redirect(operator_admin_plan_categories_path)
    else
      flash[:error] = "Something went wrong."
      turbo_redirect(new_operator_admin_plan_category_path)
    end
  end

  def update
    find_plan_category
    
    if @plan_category.update(plan_category_params)
      flash[:notice] = "Plan Category updated."
      turbo_redirect(operator_admin_plan_categories_path)
    else
      flash[:error] = "Something went wrong."
      turbo_redirect(new_operator_admin_plan_category_path)
    end
  end

  private

  def find_plan_categories
    @plan_categories = PlanCategory.order(name: :desc).all
  end

  def find_plan_category(key=:id)
    @plan_category = PlanCategory.find(params[key])
  end

  def plan_category_params
    params.require(:plan_category).permit(:name, plan_ids: []).merge( { operator_id: current_tenant.id } )
  end
end