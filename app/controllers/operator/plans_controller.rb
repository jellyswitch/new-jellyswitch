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

    if @plan.save
      flash[:notice] = "Plan saved."
      turbolinks_redirect(plan_path(@plan))
    else
      render :new, status: 422
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

    @plan.update_attributes(plan_params)
    
    if @plan.save
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
    turbolinks_redirect(plan_path(@plan), action: "advance")
  end

  private

  def find_plans
    @plans = Plan.all
  end

  def find_plan(key=:id)
    @plan = Plan.friendly.find(params[key])
  end

  def plan_params
    params.require(:plan).permit(:name, :interval, :amount_in_cents, :visible, :available)
  end
end