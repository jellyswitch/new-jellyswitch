class  OnboardingController < ApplicationController
  def new_user
  end

  def create_user
    result = Onboarding::CreateAccount.call(
      email: params[:email]
    )

    log_in(result.user)
    turbolinks_redirect(new_user_info_onboarding_index_path, action: "replace")
  end

  def new_user_info
    @user = current_user
  end

  def create_user_info
    @user = current_user

    @user.operator.update(name: params[:operator_name])

    @user.update(
      name: params[:name],
      password: params[:password]
    )

    redirect_to landing_url(subdomain: @user.operator.subdomain)
  end
end