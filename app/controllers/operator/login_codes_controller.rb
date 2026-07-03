class Operator::LoginCodesController < Operator::BaseController
  skip_before_action :reset_location, only: [:new, :create, :verify_form, :verify]
  before_action :background_image

  # Step 1 — request form (enter email).
  def new
  end

  # Step 1 (submit) — email a Login Code, then advance to the verify form.
  # Always advances regardless of whether the email has an account, so the
  # page never reveals account existence (mirrors the API + forgot_password).
  def create
    @email = params[:email].to_s.downcase.strip
    user = User.find_by_operator(email: @email, operator_id: current_tenant.id)

    if user
      begin
        user.generate_login_code
        user.send_login_code_email
      rescue => e
        Honeybadger.notify(e)
        Rails.logger.error("Web login code email failed: #{e.message}")
      end
    end

    flash[:success] = "If an account exists for that email, we've sent a 6-digit login code. It expires in 10 minutes."
    turbo_redirect(login_code_verify_path(email: @email), action: "replace")
  rescue Pundit::NotAuthorizedError, ActiveRecord::RecordNotFound
    raise
  rescue => e
    Honeybadger.notify(e)
    flash[:error] = "An error occurred. Please try again."
    turbo_redirect(new_login_code_path, action: "replace")
  end

  # Step 2 — code-entry form.
  def verify_form
    @email = params[:email].to_s.downcase.strip
    render :verify
  end

  # Step 2 (submit) — verify the code and log in (same as password login).
  def verify
    @email = params[:email].to_s.downcase.strip
    user = User.find_by_operator(email: @email, operator_id: current_tenant.id)

    if user&.verify_login_code(params[:code])
      log_in(user)
      remember(user)
      if ios_request?
        turbo_redirect(mobile_send_user_id_to_ios_path, action: restore_if_possible)
      else
        redirect_to_stored_location_or_default(landing_path)
      end
    else
      flash.now[:error] = "That code is invalid or has expired. Request a new one if you need to."
      render :verify, status: :unprocessable_entity
    end
  rescue Pundit::NotAuthorizedError, ActiveRecord::RecordNotFound
    raise
  rescue => e
    Honeybadger.notify(e)
    flash[:error] = "An error occurred. Please try again."
    turbo_redirect(new_login_code_path, action: "replace")
  end

  private

  def redirect_to_stored_location_or_default(default_path)
    path = session.delete(:return_to) || default_path
    turbo_redirect(path, action: :advance)
  end
end
