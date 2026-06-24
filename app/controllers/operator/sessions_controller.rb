class Operator::SessionsController < Operator::BaseController
  skip_before_action :reset_location, only: [:new, :create, :destroy]
  before_action :background_image

  def new
    authorize :session, :new?
  end

  def create
    authorize :session, :create?

    # Bots/scanners POST to /login with no (or an empty) `session` param,
    # which Rails drops entirely — guard so we redirect instead of 500ing on nil.
    if params[:session].blank?
      flash[:error] = "Please enter your email and password."
      turbo_redirect(login_path, action: "replace")
      return
    end

    @email = params[:session][:email].downcase
    @operator = current_tenant

    result = Authenticate.call(
      email: @email,
      operator: @operator,
      password: params[:session][:password],
    )

    if result.success?
      # Unconfirmed members used to be HARD-BLOCKED here, which stranded real
      # signups who never clicked the confirmation link (and was inconsistent
      # with the mobile/API path, which never blocked them). We now let them in
      # and surface a persistent "verify your email" nudge via the operator
      # layout (see layouts/_verify_email_banner) — keeping the confirmation
      # email flow intact (resend lives in that banner). Front-door spam is
      # handled before a User even exists (reCAPTCHA, honeypot, disposable-email
      # + MX validators), so the gate here only punished legitimate users.
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
