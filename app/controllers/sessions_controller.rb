class SessionsController < ApplicationController
  def new
    authorize :session, :new?
  end

  def create
    authorize :session, :create?
    user = User.find_by(email: params[:session][:email].downcase)
    if user && user.authenticate(params[:session][:password])
      log_in(user)
      remember(user)
      redirect_to home_url(subdomain: user.operator.subdomain)
    else
      flash[:error] = "Invalid email/password combination."
      # render status: 422
    end
  end
end
