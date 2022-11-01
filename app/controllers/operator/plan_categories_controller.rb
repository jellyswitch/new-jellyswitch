class Operator::PlanCategoriesController < Operator::BaseController
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
      turbo_redirect(plan_categories_path)
    else
      flash[:error] = "Something went wrong."
      turbo_redirect(new_plan_category_path)
    end
  end

  private

  def find_plan_categories
    @plan_categories = PlanCategory.order(name: :desc).all
  end

  def plan_category_params
    params.require(:plan_category).permit(:name)
  end
end