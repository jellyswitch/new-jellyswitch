
class Operator::PlansController < Operator::BaseController
  include PlansHelper
  before_action :background_image

  def index
    find_plans
    authorize @plans
  end

  def archived
    find_plans
    authorize @plans
  end

  def new
    @plan = Plan.new
    authorize @plan
  end

  def create
    @plan = Plan.new(plan_params)
    authorize @plan

    result = Billing::Plans::CreatePlan.call(
      plan: @plan,
      operator: current_tenant,
      location: current_location
    )

    if result.success?
      flash[:notice] = "Plan saved."
      if params[:add_plan_and_add_another].present?
        turbo_redirect(new_plan_path, action: "replace")
      else
        turbo_redirect(plan_path(@plan))
      end
    else
      flash[:error] = result.message
      turbo_redirect(new_plan_path)
    end
  end

  def show
    find_plan
    authorize @plan
  end

  def edit
    find_plan
    authorize @plan
  end

  def update
    find_plan
    authorize @plan

    if @plan.update(plan_update_params)
      flash[:notice] = "Plan updated."
      turbo_redirect(plan_path(@plan))
    else
      render :edit, status: 422
    end
  end

  def destroy
    find_plan
    authorize @plan

    @plan.update(available: false)
    if @plan.save
      flash[:notice] = "Plan archived."
      turbo_redirect(plans_path)
    else
      flash[:error] = "Unable to archive plan: #{@plan.name}"
      turbo_redirect(referrer_or_root)
    end
  rescue => e
    Honeybadger.notify(e)
    flash[:error] = "An error occurred: #{e.message}"
    turbo_redirect(referrer_or_root)
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
    turbo_redirect(plans_path, action: "advance")
  rescue => e
    Honeybadger.notify(e)
    flash[:error] = "An error occurred: #{e.message}"
    turbo_redirect(referrer_or_root)
  end

  def toggle_visibility
    find_plan(:plan_id)
    authorize @plan
    
    result = ToggleValue.call(object: @plan, value: :visible)
    
    if !result.success?
      flash[:error] = result.message
    end
    turbo_redirect(plan_path(@plan), action: "replace")
  end

  def toggle_availability
    find_plan(:plan_id)
    authorize @plan
    
    result = ToggleValue.call(object: @plan, value: :available)
    
    if !result.success?
      flash[:error] = result.message
    end
    turbo_redirect(plan_path(@plan), action: "replace")
  end

  private

  def find_plans
    @plans = Plan.individual.for_location(current_location).order(:name)
  end

  def find_plan(key=:id)
    @plan = Plan.friendly.find(params[key])
  end

  def plan_update_params
    p = params.require(:plan).permit(:visible,
      :available, :building_access_level,
      :credits, :description, :plan_category_id, :childcare_reservations,
      :included_meeting_room_minutes, :overage_rate_in_cents,
      :has_day_limit, :day_limit, :commitment_interval,
      :featured, :display_order, :features_text, :features_default,
      location_ids: [])
    convert_meeting_room_params!(p)
    if p.key?(:features_text)
      lines = p.delete(:features_text).to_s.split(/\r?\n/).map(&:strip).reject(&:blank?)
      defaults = p.delete(:features_default).to_s.split(/\r?\n/).map(&:strip).reject(&:blank?)
      # The form prefills the automatic lines; saving them untouched keeps the
      # product on automatic, so later config changes still flow to the website.
      p[:features] = lines == defaults ? [] : lines
    end
    p
  end
end
