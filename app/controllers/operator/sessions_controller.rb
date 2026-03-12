class Operator::SessionsController < Operator::BaseController
  skip_before_action :reset_location, only: [:new, :create, :destroy]
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
      # Block unconfirmed email users (staff roles bypass this check)
      if !result.user.email_confirmed? && result.user.role == User::UNASSIGNED
        flash[:error] = "Please verify your email address. Check your inbox for a confirmation link."
        turbo_redirect(login_path, action: "replace")
        return
      end

      log_in(result.user)
      remember(result.user)

      if ios_request?
        turbo_redirect(mobile_send_user_id_to_ios_path, action: restore_if_possible)
      else
        redirect_to_stored_location_or_default(landing_path)
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

  private

  def redirect_to_stored_location_or_default(default_path)
    path = session.delete(:return_to) || default_path
    turbo_redirect(path, action: :advance)
  end
end
