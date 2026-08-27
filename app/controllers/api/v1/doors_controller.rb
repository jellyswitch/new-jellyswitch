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
    # Gate on the DOOR's building, not the requester's home location: the id
    # is client-supplied, so at a multi-location operator a forged unlock for
    # another location's door must be checked against access AT that door's
    # location. The approach path (AutoUnlocksController, beacon.location)
    # and the web path (Api::DoorsController, @door.location) already gate
    # this way — this manual path was the one divergence. Using the door's
    # location here also keys ConsumeOnEntry's bundle burn to the building
    # actually entered, matching both other paths. The fallback only covers
    # legacy location-less door rows (Kisi couldn't unlock those anyway — the
    # API key lives on door.location).
    location = door.location || current_location
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
        # Tell an unapproved member the truth — they're pending screening —
        # instead of steering them to buy a pass that won't open the door yet
        # (the exact trap from the Nash incident, 2026-08-07).
        message = if !user.approved? && !user.superadmin? && !user.admin_or_manager?(location)
          "Your account is pending approval. You'll get building access as soon as the team approves you."
        else
          "You don't have access today. Buy a day pass or activate a membership to unlock the doors."
        end
        return render json: {
          success: false,
          door:    door.name,
          message: message,
        }, status: :forbidden
      end
    end

    begin
      result = perform_unlock(door: door, user: user, location: location, method: "manual")
      # Kisi answers 2xx only when the door actually fired. A controller-offline
      # blip (fac001, Zephyr Cove 2026-08-13 / 2026-08-27) comes back as a non-2xx
      # the client wraps in success:false — before this check the member was told
      # "Door unlocked" while the door stayed shut, so they kept re-tapping.
      if result[:success]
        render json: { success: true, door: door.name, message: "Door unlocked" }
      else
        render json: {
          success: false,
          door:    door.name,
          message: "The door system is offline right now. Please try again in a minute.",
        }
      end
    rescue => e
      render json: { success: false, door: door.name, message: e.message }
    end
  end
end
