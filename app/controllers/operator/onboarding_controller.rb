class Operator::OnboardingController < Operator::BaseController
  before_action :background_image
  before_action :authorize_onboarding
  include PlansHelper
  include DayPassTypesHelper
  include RoomsHelper
  include UsersHelper

  def new
  end

  def new_membership_plan
    @plan = current_tenant.plans.new
  end

  def create_membership_plan
    @plan = Plan.new(plan_params)

    result = Billing::Plans::CreatePlan.call(
      plan: @plan,
      operator: current_tenant,
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

  def add_members
  end

  def new_member
    @user = current_tenant.users.new
  end

  def create_member
    result = CreateUser.call(params: user_params, operator: current_tenant)

    if result.success?
      flash[:success] = "Member #{result.user.name} added."
      if params[:add_member_and_create_another].present?
        turbolinks_redirect(new_member_operator_onboarding_index_path, action: "replace")
      else
        turbolinks_redirect(new_operator_onboarding_path, action: "replace")
      end
    else
      flash[:error] = result.message
      render :new_member, status: 422
    end
  end

  def new_kisi
  end

  def create_kisi
    api_key = params[:kisi_api_key]
    if api_key.blank?
      flash[:error] = "Please enter an API key below."
      render :new_kisi
    else
      current_tenant.update(kisi_api_key: api_key)
      turbolinks_redirect(new_door_operator_onboarding_index_path)
    end
  end

  def new_door
  end

  def create_door
  end

  def skip
    current_tenant.update(skip_onboarding: true)
    turbolinks_redirect(feed_items_path)
  end

  private

  def authorize_onboarding
    authorize :onboarding, :show?
  end
end
