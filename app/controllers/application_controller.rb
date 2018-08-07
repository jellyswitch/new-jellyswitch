class ApplicationController < ActionController::Base
  include ApplicationHelper
  include Pundit

  rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized

  def user_not_authorized
    flash[:warning] = "You are not authorized to perform that action."
    redirect_to(request.referrer || root_path)
  end
end
