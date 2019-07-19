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
      turbolinks_redirect(landing_url(subdomain: result.user.operator.subdomain), action: "replace")
    else
      flash[:error] = result.message
      turbolinks_redirect(new_user_info_onboarding_index_path, action: "replace")
    end
  end
end