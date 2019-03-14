class Operator::SessionsController < Operator::BaseController
  def new
    authorize :session, :new?
    background_image
  end

  def create
    authorize :session, :create?
    user = User.find_by_operator(email: params[:session][:email].downcase, operator_id: current_tenant.id)
    if user && user.authenticate(params[:session][:password])
      log_in(user)
      remember(user)
      turbolinks_redirect(landing_path)
    else
      flash[:error] = "Invalid email/password combination."
      background_image
      render :new
      # render status: 422
    end
  end

  def destroy
    log_out
    # render destroy.js.erb
    # OLD: redirect_to root_path
  end
end
