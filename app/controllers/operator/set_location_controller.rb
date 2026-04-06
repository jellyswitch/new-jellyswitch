
class Operator::SetLocationController < Operator::BaseController
  before_action :background_image
  include SessionsHelper

  def edit
  end

  def update
    location = Location.find(location_params[:id])
    update_location(location)

    Rails.logger.warn "[SET_LOCATION] after update: session_loc=#{session[:location_id]} cookie_loc=#{cookies.signed[:location_id]} location=#{location.id}"
    turbo_redirect(root_path)
  rescue ActiveRecord::RecordNotFound => e
    Honeybadger.notify(e)
    flash[:error] = 'There was a problem finding that location.'
    turbo_redirect(root_path)
  end

  private

  def location_params
    params.require(:location).permit(:id)
  end
end
