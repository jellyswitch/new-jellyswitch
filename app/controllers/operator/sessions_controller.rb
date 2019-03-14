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
      background_image
      render :new, status: 422
    end
  end

  def destroy
    log_out
    turbolinks_redirect(root_path)
  end
end
