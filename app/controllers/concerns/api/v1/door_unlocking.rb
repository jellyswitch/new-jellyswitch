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
    return true if location && user.has_active_lease?(location)

    day_start = today.in_time_zone(zone).beginning_of_day
    day_end   = today.in_time_zone(zone).end_of_day
    user.reservations
        .where(cancelled: false)
        .where(datetime_in: day_start..day_end)
        .any?
  end

  def call_kisi_unlock(door, location)
    url = "https://api.kisi.io/locks/#{door.kisi_id}/unlock"
    HTTParty.post(url, headers: {
      "Authorization" => "KISI-LOGIN #{location.kisi_api_key}",
      "Content-type"  => "application/json",
      "Accept"        => "application/json",
    }).parsed_response
  end

  def perform_unlock(door:, user:, location:, method:)
    DoorPunch.create!(user: user, door: door, operator: current_tenant, method: method)
    response = call_kisi_unlock(door, location)
    DoorPunch.create!(user: user, door: door, operator: current_tenant, method: method, json: response)
    response
  end
end
