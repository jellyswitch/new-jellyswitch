class Api::V1::DoorsController < Api::V1::BaseController
  include Api::V1::DoorUnlocking

  def index
    location = current_location
    return render json: [] unless location

    # Gate the Keys tab on the SAME predicate the unlock endpoint uses, so
    # door rows show if and only if a tap would succeed. PR #467 (d56bea15)
    # hid rows that would 403 (paused-membership-no-day-pass users), but it
    # gated on Permissions#has_building_access?, which lacks the reservation
    # ±window clause (ADR 0013) — so a reservation-only visitor whom unlock
    # would admit saw an empty Keys tab and was stranded at the door.
    return render json: [] unless user_can_access_building?(current_api_user, location)

    doors = location.doors.where(available: true)
    # `private` is opt-in (a door is admin-only only when explicitly true). Treat
    # an unset/NULL flag as public — `where(private: false)` drops NULL rows in
    # SQL, which silently hid never-flagged doors from members. Matches the
    # NULL-tolerant filter used in the web/landing/door-access controllers.
    doors = doors.where(private: [false, nil]) unless current_api_user.admin?
    # Room Locks never render in the general Keys list — the reservation is
    # the key (ADR 0021). Staff keep the full door list.
    doors = doors.where(room_id: nil) unless current_api_user.admin?

    render json: doors.map { |d| { id: d.id, name: d.name, private: d.private } }
  end

  def punches
    door = Door.find(params[:id])
    punches = DoorPunch.where(door: door, user: current_api_user)
      .order(created_at: :desc)
      .limit(30)

    render json: punches.map { |p|
      {
        id: p.id,
        door_name: door.name,
        timestamp: p.created_at.strftime("%B %e, %Y at %l:%M %p"),
      }
    }
  end

  def unlock
    door     = Door.find(params[:id])
    location = current_location
    user     = current_api_user

    if door.room_lock?
      unless user_can_open_room_lock?(user, door)
        return render json: {
          success: false,
          door:    door.name,
          message: "#{door.room.name} opens with a reservation. Book the room to unlock it.",
        }, status: :forbidden
      end
    else
      # Private doors are admin/staff-only — a member with building access must
      # not open one just because they know its id (the Keys list hides them).
      if door.private? && !user.admin_or_manager?(door.location)
        return render json: {
          success: false,
          door:    door.name,
          message: "#{door.name} is a restricted door.",
        }, status: :forbidden
      end

      unless user_can_access_building?(user, location)
        return render json: {
          success: false,
          door:    door.name,
          message: "You don't have access today. Buy a day pass or activate a membership to unlock the doors.",
        }, status: :forbidden
      end
    end

    begin
      perform_unlock(door: door, user: user, location: location, method: "manual")
      render json: { success: true, door: door.name, message: "Door unlocked" }
    rescue => e
      render json: { success: false, door: door.name, message: e.message }
    end
  end
end
