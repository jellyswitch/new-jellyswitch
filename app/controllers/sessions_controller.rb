class SessionsController < ApplicationController
  def new
    background_image
  end

  def create
    user = User.find_by(email: params[:session][:email].downcase)
    if user && user.authenticate(params[:session][:password])
      log_in(user)
      remember(user)
      redirect_to users_path
    else
      flash[:error] = "Invalid email/password combination."
      render 'new'
    end
  end

  def destroy
    log_out
    redirect_to root_path
  end
end
