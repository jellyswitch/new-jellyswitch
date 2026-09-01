class Api::DoorsController < ApplicationController
  include DoorsHelper
  include Api::V1::DoorUnlocking
  skip_forgery_protection
  before_action :authenticate_api_user

  def index
    location = current_location || current_user&.current_location || current_user&.original_location

    if location.nil?
      render json: { error: "No location set" }, status: 400
      return
    end

    # Mirror the mobile Keys list (Api::V1::DoorsController#index): a member
    # without current building access (paused membership, lapsed plan, no day
    # pass) gets an empty list rather than the enumerable public door names/ids.
    # has_building_access? already admits all staff (superadmin/admin/CM/GM).
    return render json: [] unless current_user.has_building_access?(location)

    doors = location.doors.available
    # Room Locks never render in the general Keys list — the reservation is
    # the key (ADR 0021). Staff keep the full door list.
    doors = doors.where(room_id: nil) unless current_user.admin?
    # Private doors are admin-only. The mobile Keys list already hid them; this
    # endpoint was missing the filter, so a member with building access could
    # see + open a private door (e.g. Untethered "Pipkin Suite"). NULL-tolerant
    # so a never-flagged door stays public.
    doors = doors.where(private: [false, nil]) unless current_user.admin?
    render json: doors.map { |d| { id: d.id, name: d.name, private: d.private } }
  rescue => e
    Rails.logger.error("[DoorsAPI] Error in index: #{e.class}: #{e.message}")
    render json: { error: e.message }, status: 500
  end

  def unlock
    @door = Door.find(params[:id])
    operator = current_tenant || @door.operator

    # Set tenant context if missing (XHR requests may not have session tenant)
    ActsAsTenant.current_tenant = operator if ActsAsTenant.current_tenant.nil?

    # ADR 0021: a Room Lock is reservation-gated — staff anytime, otherwise
    # only the reservation holder during their booking. This is the endpoint
    # the web Keys page's unlock buttons hit, so members reach it directly.
    if @door.room_lock?
      unless @door.openable_as_room_lock_by?(current_user)
        return render json: {
          success: false,
          door:    @door.name,
          message: "#{@door.room.name} opens with a reservation. Book the room to unlock it.",
        }, status: :forbidden
      end
    else
      # Private doors are admin/staff-only — a member with building access must
      # not open one just because they know its id (the Keys list hides them from
      # members). Staff = admins/managers/superadmins of the door's location.
      if @door.private? && !current_user.admin_or_manager?(@door.location)
        return render json: {
          success: false,
          door:    @door.name,
          message: "#{@door.name} is a restricted door.",
        }, status: :forbidden
      end

      # Same gate as the mobile unlock (Api::V1::DoorsController#unlock) — being
      # logged in is not building access. Gated on the door's own location, not
      # the session's current_location, so a stale location pick can't widen access.
      unless user_can_access_building?(current_user, @door.location)
        return render json: {
          success: false,
          door:    @door.name,
          message: building_access_denial_message(current_user, @door.location),
        }, status: :forbidden
      end

      # Burn-on-entry parity with Api::V1::DoorUnlocking#perform_unlock: a
      # bundle-only member passes the gate above via their bundle, so a web
      # unlock must spend a bundle day exactly like a mobile unlock — otherwise
      # the Keys page is an unmetered entrance. A Room Entry never burns
      # (ADR 0021), hence the else-branch. Best-effort: a billing error
      # must not keep a member out of the building.
      begin
        Billing::DayPassBundles::ConsumeOnEntry.call(user: current_user, location: @door.location)
      rescue => e
        Rails.logger.error("[DoorOpen:API] ConsumeOnEntry failed: #{e.class}: #{e.message}")
        Honeybadger.notify(e) rescue nil
      end
    end

    # Log the door punch. Room Entry ≠ door punch (ADR 0021): a Room Lock
    # open is audited but flagged out of building-entry semantics.
    punch = DoorPunch.create!(user: current_user, door: @door, operator: operator,
                              room_entry: @door.room_lock?)

    # Call Kisi API to physically unlock the door
    begin
      kisi_url = url(@door)
      kisi_result = HTTParty.post(kisi_url, headers: headers(@door))
      punch.update(json: kisi_result.parsed_response)
      Rails.logger.info("[DoorOpen:API] #{@door.name} kisi_id=#{@door.kisi_id} => #{kisi_result.code}")

      if kisi_result.success?
        render json: { success: true, door: @door.name, message: "#{@door.name} unlocked" }
      else
        Rails.logger.error("[DoorOpen:API] Kisi error: #{kisi_result.code} #{kisi_result.body}")
        render json: { success: false, door: @door.name, message: "Failed to unlock #{@door.name}" }, status: 502
      end
    rescue => e
      Rails.logger.error("[DoorOpen:API] Error unlocking #{@door.name}: #{e.class}: #{e.message}")
      render json: { success: false, message: "Error: #{e.message}" }, status: 500
    end
  end

  private

  def authenticate_api_user
    unless current_user
      render json: { error: "Unauthorized" }, status: 401
    end
  end
end
