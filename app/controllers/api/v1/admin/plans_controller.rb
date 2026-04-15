class Api::V1::Admin::PlansController < Api::V1::Admin::BaseController
  def index
    plans = Plan.where(operator: current_tenant, plan_type: 'individual').order(:amount_in_cents)
    plans = plans.where(available: true) unless params[:include_archived]

    render json: plans.map { |p| plan_json(p) }
  end

  def create
    plan = Plan.new(plan_params)
    plan.operator = current_tenant

    if plan.save
      render json: plan_json(plan), status: :created
    else
      render_error(plan.errors.full_messages.join(', '))
    end
  end

  def update
    plan = Plan.find(params[:id])

    if plan.update(plan_params)
      render json: plan_json(plan)
    else
      render_error(plan.errors.full_messages.join(', '))
    end
  end

  def toggle_visibility
    plan = Plan.find(params[:id])
    plan.update(visible: !plan.visible)
    render json: plan_json(plan)
  end

  def toggle_availability
    plan = Plan.find(params[:id])
    plan.update(available: !plan.available)
    render json: plan_json(plan)
  end

  private

  def plan_params
    params.require(:plan).permit(:name, :amount_in_cents, :interval, :available, :visible, :plan_type, :plan_category_id, :credits, :day_limit, :has_day_limit)
  end

  def plan_json(p)
    {
      id: p.id,
      name: p.name,
      amount_in_cents: p.amount_in_cents,
      interval: p.interval,
      available: p.available,
      visible: p.visible,
      category_name: p.plan_category&.name,
      subscriber_count: p.subscriptions.count,
    }
  end
end
