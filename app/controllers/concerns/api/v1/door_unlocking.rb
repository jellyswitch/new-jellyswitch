module Api::V1::DoorUnlocking
  extend ActiveSupport::Concern

  private

  def user_can_access_building?(user, location)
    return false if user.nil?
    return true if user.superadmin?
    return true if location && user.admin_or_manager?(location)

    zone  = location&.time_zone.presence || "UTC"
    today = Time.current.in_time_zone(zone).to_date

    return true if user.has_active_subscription?
    return true if user.day_passes.where(day: today).any?
    return true if location && user.has_active_day_pass_bundle?(location)
    return true if location && user.has_active_lease?(location)

    # A reservation grants access only inside its ±window (ADR 0013), not all
    # day. Coarse-filter candidates by datetime_in (±(1 day + window) catches
    # midnight spillover and any reasonable duration), then make the exact in/out
    # call in Ruby. window_minutes is passed through so access_window_open? needn't
    # reload the operator per row.
    window_minutes = location&.operator&.building_access_window_minutes || 60
    now = Time.current
    window = window_minutes.minutes
    user.reservations
        .where(cancelled: false)
        .where(datetime_in: (now - 1.day - window)..(now + 1.day + window))
        .any? { |reservation| reservation.access_window_open?(now, window_minutes: window_minutes) }
  end

  def call_kisi_unlock(door, _location = nil)
    # Routed through Kisi::Client so the manual /doors/:id/unlock path
    # benefits from the same persistent connection the async job uses.
    # `location` is ignored (Kisi::Client reads door.location internally).
    Kisi::Client.unlock(door)[:parsed]
  end

  def perform_unlock(door:, user:, location:, method:)
    DoorPunch.create!(user: user, door: door, operator: current_tenant, method: method)
    begin
      Billing::DayPassBundles::ConsumeOnEntry.call(user: user, location: location)
    rescue => e
      Rails.logger.error("[DoorUnlocking] ConsumeOnEntry failed: #{e.class}: #{e.message}")
      Honeybadger.notify(e) rescue nil
    end
    response = call_kisi_unlock(door, location)
    DoorPunch.create!(user: user, door: door, operator: current_tenant, method: method, json: response)
    response
  end
end
