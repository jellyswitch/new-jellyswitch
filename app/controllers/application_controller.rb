
class ApplicationController < ActionController::Base
  layout "application"
  include ApplicationHelper
  include SessionsHelper
  include Pagy::Backend
  include Pundit

  skip_forgery_protection

  rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized

  def user_not_authorized
    flash[:alert] = "Whoops! That's not allowed. If this isn't what you were expecting, please contact our staff."
    redirect_to referrer_or_root
  end

  protected

  def include_stripe
    @include_stripe = true
  end

  def referrer_or_root
    request.referrer || root_path
  end

  def turbo_redirect(path, action: "replace")
    @redirect_path = path

    @action = action
    flash.keep
    response.headers["Turbo-Location"] = path
    respond_to do |format|
      format.js do
        render "shared/turbo_redirect"
      end
      format.html do
        redirect_to path, allow_other_host: true
      end
    end
  end
end
