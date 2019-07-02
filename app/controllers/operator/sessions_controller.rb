# typed: false
class Operator::SessionsController < Operator::BaseController
  def new
    authorize :session, :new?
    background_image
  end

  def create
    authorize :session, :create?
    user = User.find_by_operator(email: params[:session][:email].downcase, operator_id: current_tenant.id)
    if user.present?
      if user.authenticate(params[:session][:password])
        log_in(user)
        remember(user)
        turbolinks_redirect(landing_path, action: "restore")
      else
        background_image
        flash[:error] = "Invalid password."
        render :new, status: 422
      end
    else
      flash[:error] = "Please check that your email and password are accurate."
      turbolinks_redirect(login_path)
    end
  rescue Exception => e
    Rollbar.error(e)
    flash[:error] = "An error occurred: #{e.message}"
    turbolinks_redirect(referrer_or_root)
  end

  def destroy
    log_out
    turbolinks_redirect(root_path, action: "restore")
  end
end
