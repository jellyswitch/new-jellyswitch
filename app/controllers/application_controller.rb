class ApplicationController < ActionController::Base
  layout "application"
  include ApplicationHelper
  include SessionsHelper
  include Pundit

  rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized

  def user_not_authorized
    flash[:alert] = "Whoops! That's not allowed. If this isn't what you were expecting, please contact #{current_tenant.contact_name} by calling #{current_tenant.contact_phone}."
    redirect_to referrer_or_root
  end

  protected

  def include_stripe
    @include_stripe = true
  end

  def referrer_or_root
    request.referrer || root_path
  end
end
