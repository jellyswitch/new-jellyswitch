class Operator::OnboardingController < Operator::BaseController
  before_action :background_image
  include PlansHelper
  include DayPassTypesHelper
  include RoomsHelper

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

  def new_day_pass_type
    @day_pass_type = current_tenant.day_pass_types.new
  end

  def create_day_pass_type
    result = CreateDayPassType.call(params: day_pass_type_params)

    @day_pass_type = result.day_pass_type

    if result.success?
      if params[:add_day_pass_type_and_add_another].present?
        turbolinks_redirect(new_day_pass_type_operator_onboarding_index_path, action: "replace")
      else
        turbolinks_redirect(new_operator_onboarding_path)
      end
    else
      flash[:error] = result.message
      render :new_day_pass_type, status: 422
    end
  end

  def new_room
    @room = current_location.rooms.new
  end

  def create_room
    @room = Room.new(room_params)

    if @room.save
      flash[:success] = "Room added."
      if params[:add_room_and_add_another].present?
        turbolinks_redirect(new_room_operator_onboarding_index_path, action: "replace")
      else
        turbolinks_redirect(new_operator_onboarding_path)
      end
    else
      render :new_room, status: 422
    end
  end
end