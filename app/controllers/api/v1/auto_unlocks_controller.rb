class Api::V1::AutoUnlocksController < Api::V1::BaseController
  include Api::V1::DoorUnlocking

  NONCE_TTL = 60.seconds

  def create
    uuid  = params[:uuid].to_s
    major = params[:major]
    minor = params[:minor]
    nonce = params[:nonce].to_s

    return render_error("nonce required") if nonce.blank?
    return render_error("nonce already used", status: :conflict) unless claim_nonce!(nonce)

    beacon = Beacon.available
                   .where(operator: current_tenant)
                   .find_by(uuid: uuid, major: major, minor: minor)
    return render_error("Unknown beacon", status: :not_found) if beacon.nil?

    door = beacon.door
    return render_error("Beacon is not yet assigned to a door") if door.nil?
    return render_error("Door is not configured for unlock")    if door.kisi_id.blank?
    # V1: Room Locks are excluded from approach-unlock (ADR 0021) — the
    # reservation card is the room's key; auto-popping a meeting-room door
    # for anyone walking past is wrong for non-holders and creepy for holders.
    return render_error("This door opens from your reservation, not by approach") if door.room_lock?

    location = beacon.location
    user     = current_api_user

    unless user_can_access_building?(user, location)
      return render json: {
        success: false,
        door:    door.name,
        message: building_access_denial_message(user, location),
      }, status: :forbidden
    end

    # Optimistic: log the attempt as pending, hand the slow Kisi round-trip
    # to a background job, and return immediately. The member's tap +
    # Face ID already happened in the foreground; making them wait on
    # Kisi's 1-3s here is the latency they were feeling. KisiUnlockJob
    # reconciles the punch to "unlocked"/"failed" and the admin
    # beacon-health / activity feed surfaces any failures.
    punch = DoorPunch.create!(
      user: user, door: door, operator: current_tenant, method: "auto", status: "pending",
    )
    begin
      Billing::DayPassBundles::ConsumeOnEntry.call(user: user, location: location)
    rescue => e
      Rails.logger.error("[AutoUnlock] ConsumeOnEntry failed: #{e.class}: #{e.message}")
      Honeybadger.notify(e) rescue nil
    end
    KisiUnlockJob.perform_later(punch.id)
    render json: { success: true, door: door.name, message: "Unlocking #{door.name}…" }
  end

  private

  def claim_nonce!(nonce)
    key = "auto_unlock_nonce:#{nonce}"
    Rails.cache.write(key, 1, expires_in: NONCE_TTL, unless_exist: true)
  end
end
