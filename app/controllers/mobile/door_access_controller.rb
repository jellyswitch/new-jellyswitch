class Mobile::DoorAccessController < Operator::BaseController

  rescue_from Pundit::NotAuthorizedError, with: :not_logged_in_yet

  def index
    find_doors
    authorize @doors
    background_image
  end

  private

  def not_logged_in_yet
    turbolinks_redirect(login_path, action: :replace)
  end

  def find_doors
    @doors = Door.all
    @doors = @doors.reject{|door| door.private? } unless admin?
  end

  def find_door(key=:id)
    @door = Door.friendly.find(params[key])
  end

  def log_door_punch
    DoorPunch.create!(user: current_user, door: @door)
  end

end
