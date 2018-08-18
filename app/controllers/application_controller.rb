class ApplicationController < ActionController::Base
  include ApplicationHelper
  include Pundit

  rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized

  def user_not_authorized
    flash[:alert] = "Sorry! You are not authorized to do that."
    redirect_to(request.referrer || root_path)
  end

  protected

  def background_image
    @background_image = Rails.application.config.x.customization.background
  end
end
