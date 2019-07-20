class Operator::OnboardingController < Operator::BaseController
  before_action :background_image

  def new
  end

  def new_membership_plan
    @plan = current_tenant.plans.new
  end

  def create_membership_plan
    @plan = Plan.new(plan_params)

    result = Billing::Plans::CreatePlan.call(
      plan: @plan,
      operator: current_tenant
    )

    if result.success?
      if params[:add_plan_and_add_another].present?
        turbolinks_redirect(new_membership_plan_operator_onboarding_index_path, action: "replace")
      else
        turbolinks_redirect(new_operator_onboarding_path)
      end
    else
      render :new_membership_plan
    end
  end

  private

  def plan_params
    p = params.require(:plan).permit(:name, :plan_type, :interval, :amount_in_cents, :visible, :available, :always_allow_building_access, :has_day_limit, :day_limit)
    dollars = Money.from_amount(p[:amount_in_cents].to_i, "USD")
    p[:amount_in_cents] = dollars.cents
    p
  end


end