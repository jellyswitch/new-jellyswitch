
class Operator::SetLocationController < Operator::BaseController
  before_action :background_image
  include SessionsHelper

  # `Operator::BaseController#reset_location` returns 401 for anonymous,
  # non-GET requests when `current_location` is blank — but `update` is the
  # action that exists *to set* the current location, so an anonymous
  # visitor on a multi-location operator (Untethered, Studio Workspaces)
  # could never pick a location for the first time. Skip the guard here so
  # the chicken-and-egg is broken at exactly the action whose purpose is to
  # leave the no-location state.
  skip_before_action :reset_location, only: [:update]

  def edit
  end

  def update
    location = Location.find(location_params[:id])
    update_location(location)

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
