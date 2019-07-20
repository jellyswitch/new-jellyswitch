class  OnboardingController < ApplicationController
  def new_user
  end

  def create_user
    result = Onboarding::CreateAccount.call(
      email: params[:email]
    )

    if result.success?
      log_in(result.user)
      turbolinks_redirect(new_user_info_onboarding_index_path, action: "replace")
    else
      flash[:error] = result.message
      turbolinks_redirect(new_user_onboarding_index_path, action: "replace")
    end
  end

  def new_user_info
    @user = current_user
  end

  def create_user_info
    result = Onboarding::SetUserInfo.call(
      user: current_user,
      name: params[:name],
      password: params[:password],
      operator_name: params[:operator_name]
    )

    if result.success?
      turbolinks_redirect(new_location_onboarding_index_path, action: "replace")
    else
      flash[:error] = result.message
      turbolinks_redirect(new_user_info_onboarding_index_path, action: "replace")
    end
  end
  
  def new_location
    @operator = current_user.operator
  end
  
  def create_location
    result = Onboarding::CreateLocation.call(
      operator: current_user.operator,
      name: params[:name],
      description: params[:description],
      square_footage: params[:square_footage],
      street_address: params[:street_address],
      city: params[:city],
      state: params[:state],
      zip: params[:zip],
      time_zone: params[:time_zone]
    )

    if result.success?
      turbolinks_redirect(new_member_info_onboarding_index_path(location_id: result.location.id), action: "replace")
    else
      flash[:error] = result.message
      turbolinks_redirect(new_location_onboarding_index_path, action: "replace")
    end
  end

  def new_member_info
    @location = current_user.operator.locations.find(params[:location_id])
  end

  def create_member_info
    @location = current_user.operator.locations.find(params[:location_id])
    result = Onboarding::CreateMemberInfo.call(
      location: @location,
      wifi_name: params[:wifi_name],
      wifi_password: params[:wifi_password],
      contact_name: params[:contact_name],
      contact_phone: params[:contact_phone],
      contact_email: params[:contact_email]
    )

    if result.success?
      turbolinks_redirect(new_images_onboarding_index_path(location_id: @location.id), action: "replace")
    else
      flash[:error] = result.message
      turbolinks_redirect(new_member_info_onboarding_index_path(location_id: @location.id), action: "replace")
    end
  end

  def new_images
    @location = current_user.operator.locations.find(params[:location_id])
  end

  def create_images
    @location = current_user.operator.locations.find(params[:location_id])
    result = Onboarding::FinalizeImages.call(
      location: @location,
      logo: params[:logo_image],
      background: params[:background_image]
    )

    if result.success?
      # final redirect
      turbolinks_redirect(landing_url(subdomain: @location.operator.subdomain), action: "replace")
    else
      flash[:error] = result.message
      turbolinks_redirect(new_images_onboarding_index_path(location_id: @location.id), action: "replace")
    end
  end
end