class Operator::PasswordResetsController < Operator::BaseController
  before_action :background_image

  def new
  end

  def create
    @user = User.find_by_operator(email: params[:password_reset][:email].downcase, operator_id: current_tenant.id)

    if @user
      @user.create_reset_digest
      @user.send_password_reset_email
      flash[:success] = "Email sent with password reset instructions"
      turbo_redirect(root_path, action: "replace")
    else
      flash[:error] = "Email address not found."
      turbo_redirect(new_password_reset_path, action: "replace")
    end
  rescue Pundit::NotAuthorizedError, ActiveRecord::RecordNotFound
    raise
  rescue => e
    Honeybadger.notify(e)
    flash[:error] = "An error occurred: #{e.message}"
    turbo_redirect(referrer_or_root)
  end

  def edit
    return unless authorize_reset_link!
  end

  def update
    return unless authorize_reset_link!

    if params.dig(:user, :password).blank?
      @user.errors.add(:password, "can't be empty")
      render "edit", status: :unprocessable_entity
    elsif @user.update(user_params)
      @user.clear_reset_digest!
      log_in @user
      flash[:success] = "Password has been reset."
      turbo_redirect(root_path, action: "replace")
    else
      render "edit", status: :unprocessable_entity
    end
  rescue Pundit::NotAuthorizedError, ActiveRecord::RecordNotFound
    raise
  rescue => e
    Honeybadger.notify(e)
    flash[:error] = "An error occurred: #{e.message}"
    turbo_redirect(referrer_or_root)
  end

  private

  # Authenticates the reset link and sets @user. Returns false (having already
  # redirected) when the link isn't good for anything.
  #
  # This used to identify the user from the `email` QUERY PARAM alone and never
  # look at params[:id] — the token was used only to build the form's action
  # URL. That meant anyone who knew a member's email address could POST the
  # forgot-password form to arm `reset_sent_at`, then open
  # /password_resets/<anything>/edit?email=<victim> and set a new password,
  # without ever seeing the emailed link. Verify the token itself.
  def authorize_reset_link!
    @user = find_user

    # One message and one destination for "no such user", "no reset pending"
    # and "wrong token" alike — distinguishing them would turn this page into
    # an email-enumeration oracle.
    unless @user&.valid_reset_token?(params[:id])
      flash[:error] = "That password reset link is invalid. Please request a new one."
      turbo_redirect(new_password_reset_path, action: "replace")
      return false
    end

    if @user.password_reset_expired?
      flash[:error] = "Password reset has expired."
      turbo_redirect(new_password_reset_path, action: "replace")
      return false
    end

    true
  end

  def find_user
    email = params[:email].to_s.downcase
    return nil if email.blank?

    User.find_by_operator(email: email, operator_id: current_tenant.id)
  end

  def user_params
    params.require(:user).permit(:password, :password_confirmation)
  end
end
