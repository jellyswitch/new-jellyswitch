# typed: false
class Operator::SessionsController < Operator::BaseController
  before_action :background_image

  def new
    authorize :session, :new?
    Rollbar.info("Operator::SessionsController#new")
  end

  def create
    authorize :session, :create?

    @email = params[:session][:email].downcase
    @operator = current_tenant

    result = Authenticate.call(
      email: @email,
      operator: @operator,
      password: params[:session][:password]
    )

    if result.success?
      log_in(result.user)
      remember(result.user)
      if untethered_ios_request?
        Rollbar.info("Operator::SessionsController#create untethered_ios_request?", edirecting_to: "mobile_door_access_path", email: @email, action: "restore")
        turbolinks_redirect(mobile_door_access_path, action: "restore")
      else
        Rollbar.info("Operator::SessionsController#create !untethered_ios_request?", edirecting_to: "landing_path", email: @email, action: "restore")
        turbolinks_redirect(landing_path, action: "restore")
      end
    else
      flash[:error] = result.message
      Rollbar.warning("Operator::SessionsController#create !result.success?", error: result.message, redirecting_to: "login_path", email: @email, operator_id: @operator.id, password: !params[:session][:password].blank?, action: "replace")
      turbolinks_redirect(login_path, action: "replace")
    end

  end

  def destroy
    log_out
    Rollbar.info("Operator::SessionsController#destroy", action: "restore", redirecting_to: "root_path")
    turbolinks_redirect(root_path, action: "restore")
  end
end
