class Mobile::DoorAccessController < Operator::BaseController
  rescue_from Pundit::NotAuthorizedError, with: :not_logged_in_yet

  def index
    find_doors
    background_image
  end

  def building_access_permissions
    user = User.find_by(id: request.headers["X-User-Id"])
    authorized = user&.has_building_access?(current_location)

    render json: { authorized: authorized }
  end

  def send_user_id_to_ios
    @redirect_path = params[:is_logout] ? root_path : landing_path

    render "mobile/door_access/send_user_id_to_ios"
  end

  def logout
    log_out
    @redirect_path = root_path
    turbo_redirect(mobile_send_user_id_to_ios_path(is_logout: true), action: restore_if_possible)
  end

  private

  def not_logged_in_yet
    turbo_redirect(login_path, action: :replace)
  end

  def find_doors
    @doors = Door.all
    @doors = @doors.reject { |door| door.private? } unless admin?
  end

  def find_door(key = :id)
    @door = Door.friendly.find(params[key])
  end

  def log_door_punch
    DoorPunch.create!(user: current_user, door: @door)
  end
end
