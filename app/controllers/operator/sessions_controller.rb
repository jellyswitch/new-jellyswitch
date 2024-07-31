class Operator::SessionsController < Operator::BaseController
  before_action :background_image

  def new
    authorize :session, :new?
  end

  def create
    authorize :session, :create?

    @email = params[:session][:email].downcase
    @operator = current_tenant

    result = Authenticate.call(
      email: @email,
      operator: @operator,
      password: params[:session][:password],
    )

    if result.success?
      log_in(result.user)
      remember(result.user)

      if ios_request?
        turbo_redirect(mobile_send_user_id_to_ios_path, action: restore_if_possible)
      else
        turbo_redirect(landing_path, action: restore_if_possible)
      end
    else
      flash[:error] = result.message
      turbo_redirect(login_path, action: "replace")
    end
  end

  def destroy
    log_out
    if ios_request?
      turbo_redirect(mobile_send_user_id_to_ios_path(is_logout: true), action: restore_if_possible)
    else
      turbo_redirect(root_path, action: restore_if_possible)
    end
  end
end
