# typed: true
class SessionsController < ApplicationController
  def new
    authorize :session, :new?
  end

  def create
    authorize :session, :create?
    user = User.find_by(email: params[:session][:email].downcase, admin: true)
    if user && user.authenticate(params[:session][:password])
      log_in(user)
      remember(user)
      if user.superadmin?
        redirect_to operators_path
      else
        redirect_to landing_url(subdomain: user.operator.subdomain)
      end
    else
      flash[:error] = "Invalid email/password combination."
      # render status: 422
    end
  end

  def destroy
    log_out
    turbolinks_redirect(root_path, action: "restore")
  end
end
