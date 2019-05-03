class Operator::PlansController < Operator::BaseController
  def index
    find_plans
    authorize @plans
    background_image
  end

  def new
    @plan = Plan.new
    authorize @plan
    background_image
  end

  def create
    @plan = Plan.new(plan_params)
    authorize @plan

    result = Billing::Plans::CreatePlan.call(
      plan: @plan,
      operator: current_tenant
    )

    if result.success?
      flash[:notice] = "Plan saved."
      turbolinks_redirect(plan_path(@plan))
    else
      flash[:error] = result.message
      turbolinks_redirect(new_plan_path)
    end
  end

  def show
    find_plan
    authorize @plan
    background_image
  end

  def edit
    find_plan
    authorize @plan
    background_image
  end

  def update
    find_plan
    authorize @plan

    if @plan.update(plan_update_params)
      flash[:notice] = "Plan updated."
      turbolinks_redirect(plan_path(@plan))
    else
      render :edit, status: 422
    end
  end

  def destroy
    find_plan
    authorize @plan

    @plan.update_attributes({available: false})
    if @plan.save
      flash[:notice] = "Plan archived."
      turbolinks_redirect(plans_path)
    else
      flash[:error] = "Unable to archive plan: #{@plan.name}"
      turbolinks_redirect(referrer_or_root)
    end
  rescue => e
    Rollbar.error(e)
    flash[:error] = "An error occurred: #{e.message}"
    turbolinks_redirect(referrer_or_root)
  end

  def unarchive
    find_plan(:plan_id)
    authorize @plan
    result = UnarchivePlan.call(plan: @plan)
    if result.success?
      flash[:success] = "Plan unarchived."
    else
      flash[:error] = result.message
    end
    turbolinks_redirect(plans_path, action: "advance")
  rescue => e
    Rollbar.error(e)
    flash[:error] = "An error occurred: #{e.message}"
    turbolinks_redirect(referrer_or_root)
  end

  private

  def find_plans
    @plans = Plan.individual.order(:name)
  end

  def find_plan(key=:id)
    @plan = Plan.friendly.find(params[key])
  end

  def plan_params
    params.require(:plan).permit(:name, :plan_type, :interval, :amount_in_cents, :visible, :available, :always_allow_building_access)
  end

  def plan_update_params
    params.require(:plan).permit(:visible, :available, :always_allow_building_access)
  end
end
