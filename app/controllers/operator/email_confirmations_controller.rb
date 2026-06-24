class Operator::EmailConfirmationsController < Operator::BaseController
  skip_before_action :reset_location
  before_action :background_image

  def show
    # Handle + in emails being decoded as spaces in URL query params
    email = params[:email]&.downcase&.gsub(' ', '+')
    @user = User.find_by_operator(email: email, operator_id: current_tenant.id)

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
  rescue Pundit::NotAuthorizedError, ActiveRecord::RecordNotFound
    raise
  rescue => e
    Honeybadger.notify(e)
    flash[:error] = "An error occurred. Please try again."
    turbo_redirect(root_path, action: "replace")
  end

  def resend
    email = params[:email]&.downcase&.gsub(' ', '+')
    @user = User.find_by_operator(email: email, operator_id: current_tenant.id)

    if @user.present? && !@user.email_confirmed?
      @user.generate_confirmation_token
      @user.send_confirmation_email
      flash[:success] = "Confirmation email resent. Please check your inbox."
    else
      flash[:error] = "Could not resend confirmation email."
    end

    # A logged-in member resending from the persistent verify-email banner
    # should land back where they were, not on the login page. Only honor a
    # safe, internal relative path (no scheme/host) to avoid an open redirect.
    turbo_redirect(safe_return_path || login_path, action: "replace")
  rescue Pundit::NotAuthorizedError, ActiveRecord::RecordNotFound
    raise
  rescue => e
    Honeybadger.notify(e)
    flash[:error] = "An error occurred. Please try again."
    turbo_redirect(root_path, action: "replace")
  end

  private

  # Accept only a single-segment-rooted relative path ("/foo", "/foo/bar"),
  # rejecting absolute URLs and protocol-relative "//evil.com" so the resend
  # button can never be turned into an open redirect.
  def safe_return_path
    path = params[:return_to].to_s
    return nil unless path.start_with?("/")
    return nil if path.start_with?("//")
    path
  end
end
