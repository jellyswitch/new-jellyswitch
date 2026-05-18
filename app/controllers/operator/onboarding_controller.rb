class Operator::OnboardingController < Operator::BaseController
  before_action :background_image
  before_action :authorize_onboarding
  include ErrorsHelper
  include PlansHelper
  include DayPassTypesHelper
  include RoomsHelper
  include UsersHelper

  def new
    @branding_incomplete = !current_tenant.logo_image.attached? ||
                           !current_tenant.terms_of_service.attached? ||
                           current_tenant.snippet.blank? ||
                           current_tenant.snippet == "Generic snippet about the space"
  end

  def new_stripe_connect
    session[:onboarding_in_progress] = true
  end

  def complete_stripe_connect
    session.delete(:onboarding_in_progress)
    if respond_to?(:turbo_redirect, true)
      turbo_redirect(new_membership_plan_operator_onboarding_index_path, action: "replace")
    else
      redirect_to new_membership_plan_operator_onboarding_index_path
    end
  end

  def new_membership_plan
    return turbo_redirect(new_day_pass_type_operator_onboarding_index_path) if current_tenant.plans.individual.count > 0
    @plan = current_location.plans.new
  end

  def create_membership_plan
    @plan = Plan.new(plan_params)

    result = Billing::Plans::CreatePlan.call(
      plan: @plan,
      operator: current_tenant,
      location: current_location
    )

    if result.success?
      if params[:add_plan_and_add_another].present?
        turbo_redirect(new_membership_plan_operator_onboarding_index_path, action: "replace")
      else
        turbo_redirect(feed_items_path, action: "replace")
      end
    else
      render :new_membership_plan
    end
  end

  def new_day_pass_type
    return turbo_redirect(new_room_operator_onboarding_index_path) if current_tenant.day_pass_types.count > 0
    @day_pass_type = current_location.day_pass_types.new
  end

  def create_day_pass_type
    result = CreateDayPassType.call(params: day_pass_type_params)

    @day_pass_type = result.day_pass_type

    if result.success?
      if params[:add_day_pass_type_and_add_another].present?
        turbo_redirect(new_day_pass_type_operator_onboarding_index_path, action: "replace")
      else
        turbo_redirect(feed_items_path, action: "replace")
      end
    else
      flash[:error] = result.message
      render :new_day_pass_type, status: 422
    end
  end

  def new_room
    return turbo_redirect(add_members_operator_onboarding_index_path) if current_tenant.rooms_enabled? && current_location.rooms.count > 0
    @room = current_location.rooms.new
  end

  def create_room
    @room = Room.new(room_params)

    if @room.save
      flash[:success] = "Room added."
      if params[:add_room_and_add_another].present?
        turbo_redirect(new_room_operator_onboarding_index_path, action: "replace")
      else
        turbo_redirect(feed_items_path, action: "replace")
      end
    else
      render :new_room, status: 422
    end
  end

  def add_members
  end

  def new_member
    @user = current_location.users.new
  end

  def create_member
    result = Users::Create.call(params: user_params, operator: current_tenant, location: current_location)

    if result.success?
      flash[:success] = "Member #{result.user.name} added."
      if params[:add_member_and_create_another].present?
        turbo_redirect(new_member_operator_onboarding_index_path, action: "replace")
      else
        turbo_redirect(feed_items_path, action: "replace")
      end
    else
      flash[:error] = result.message
      render :new_member, status: 422
    end
  end

  def new_stripe_members
    unless current_tenant.stripe_user_id.present?
      @stripe_not_connected = true
      return  # falls through to render :new_stripe_members
    end

    result = Onboarding::FetchStripeCustomers.call(location: current_location)

    if result.success?
      @customers = result.customers
    else
      flash[:error] = result.message
      turbo_redirect(add_members_operator_onboarding_index_path, action: "replace")
    end
  end

  def create_stripe_members
    # Random unguessable placeholder password — the imported member will
    # receive a password-reset email immediately after save and set their
    # own. 32 hex chars = 128 bits of entropy, infeasible to brute-force in
    # the window before the user resets.
    placeholder_password = SecureRandom.hex(16)

    user = current_tenant.users.new(
      name: params[:name],
      email: params[:email],
      stripe_customer_id: params[:stripe_customer_id],
      card_added: params[:card_added] == "true",
      password: placeholder_password,
      approved: true,
      original_location_id: current_location.id,
      current_location_id: current_location.id
    )

    user.user_payment_profiles.new(
      location_id: current_location.id,
      stripe_customer_id: params[:stripe_customer_id],
      card_added: params[:card_added] == "true"
    )

    if user.save
      # Trigger password-reset email so the imported member can set their own
      # credentials. Without this, the account is unreachable to its owner
      # (they never see the random placeholder).
      user.create_reset_digest
      user.send_password_reset_email
      flash[:success] = "Member added. Password-reset email sent to #{user.email}."
    else
      flash[:error] = errors_for(user)
    end

    turbo_redirect(new_stripe_members_operator_onboarding_index_path, action: "replace")
  end

  def new_kisi
    return turbo_redirect(new_door_operator_onboarding_index_path) if current_tenant.kisi_api_key.present?
  end

  def create_kisi
    api_key = params[:kisi_api_key]
    if api_key.blank?
      flash[:error] = "Please enter an API key below."
      render :new_kisi
    else
      current_tenant.update(kisi_api_key: api_key)
      current_location.update(kisi_api_key: api_key)
      turbo_redirect(new_door_operator_onboarding_index_path)
    end
  end

  def new_door
    result = Onboarding::GetKisiDoors.call(location: current_location || current_tenant.locations.first)

    if result.success?
      @doors = result.doors
    else
      @doors = []
      flash[:error] = result.message
    end
  end

  def create_door
    door = current_location.doors.new(
      name: params[:door_name],
      kisi_id: params[:kisi_id],
    )

    if door.save
      flash[:success] = "Door added."
    else
      flash[:error] = "There was a problem adding your door."
    end
    turbo_redirect(new_door_operator_onboarding_index_path, action: "replace")
  end

  def destroy_door
    door = current_location.doors.find_by(kisi_id: params[:kisi_id])
    if door.present?
      if door.destroy
        flash[:success] = "Door removed."
      else
        flash[:error] = "There was a problem removing that door."
      end
    else
      flash[:error] = "No such door."
    end
    turbo_redirect(new_door_operator_onboarding_index_path, action: "replace")
  end

  def skip
    current_tenant.update(skip_onboarding: true)
    turbo_redirect(feed_items_path)
  end

  private

  def authorize_onboarding
    authorize :onboarding, :show?
  end
end
