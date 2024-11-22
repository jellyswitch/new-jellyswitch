class Operator::Admin::PlanCategoriesController < Operator::BaseController
  include PlansHelper
  before_action :background_image


  def index
    find_plan_categories
    authorize @plan_categories
  end

  def new
    @plan_category = PlanCategory.new
    authorize @plan_category
  end

  def show
    find_plan_category
    authorize @plan_category
  end

  def create
    @plan_category = PlanCategory.new(plan_category_params)
    authorize @plan_category

    if @plan_category.save
      flash[:notice] = "Plan Category created."
      turbo_redirect(operator_admin_plan_category_path(@plan_category))
    else
      flash[:error] = "Something went wrong."
      turbo_redirect(new_operator_admin_plan_category_path)
    end
  end

  def update
    find_plan_category
    authorize @plan_category

    new_params = plan_category_params
    new_params[:plan_ids] = new_params[:plan_ids].concat(@plan_category.plans.map(&:id))

    if @plan_category.update(new_params)
      flash[:notice] = "Plan Category updated."
      turbo_redirect(operator_admin_plan_category_path(@plan_category))
    else
      flash[:error] = "Something went wrong."
      turbo_redirect(new_operator_admin_plan_category_path)
    end
  end

  def destroy
    find_plan_category
    authorize @plan_category

    if @plan_category.destroy
      flash[:notice] = "Plan category removed."
      turbo_redirect(operator_admin_plan_categories_path)
    else
      flash[:error] = "Something went wrong."
      turbo_redirect(new_operator_admin_plan_category_path)
    end
  end

  def remove_plan
    find_plan_category(:plan_category_id)
    @plan = current_location.plans.find(params[:plan_id])
    authorize @plan_category

    if @plan.update(plan_category_id: nil)
      flash[:notice] = "Plan removed from category."
      turbo_redirect(operator_admin_plan_category_path(@plan_category))
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
    params.require(:plan_category).permit(:name, plan_ids: []).merge( { operator_id: current_tenant.id, location_id: current_location.id } )
  end
end