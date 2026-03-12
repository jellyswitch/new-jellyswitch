class Operator::EmailConfirmationsController < Operator::BaseController
  before_action :background_image

  def show
    @user = User.find_by_operator(email: params[:email]&.downcase, operator_id: current_tenant.id)

    if @user.nil?
      flash[:error] = "Could not find an account with that email address."
      turbo_redirect(root_path, action: "replace")
    elsif @user.email_confirmed?
      flash[:success] = "Your email is already confirmed. Please log in."
      turbo_redirect(login_path, action: "replace")
    elsif @user.confirmation_expired?
      flash[:error] = "This confirmation link has expired. Please request a new one."
      turbo_redirect(login_path, action: "replace")
    elsif @user.valid_confirmation_token?(params[:id])
      @user.confirm_email!
      flash[:success] = "Email confirmed! You can now log in."
      turbo_redirect(login_path, action: "replace")
    else
      flash[:error] = "Invalid confirmation link. Please request a new one."
      turbo_redirect(login_path, action: "replace")
    end
  rescue Exception => e
    Honeybadger.notify(e)
    flash[:error] = "An error occurred. Please try again."
    turbo_redirect(root_path, action: "replace")
  end

  def resend
    @user = User.find_by_operator(email: params[:email]&.downcase, operator_id: current_tenant.id)

    if @user.present? && !@user.email_confirmed?
      @user.generate_confirmation_token
      @user.send_confirmation_email
      flash[:success] = "Confirmation email resent. Please check your inbox."
    else
      flash[:error] = "Could not resend confirmation email."
    end

    turbo_redirect(login_path, action: "replace")
  rescue Exception => e
    Honeybadger.notify(e)
    flash[:error] = "An error occurred. Please try again."
    turbo_redirect(root_path, action: "replace")
  end
end
