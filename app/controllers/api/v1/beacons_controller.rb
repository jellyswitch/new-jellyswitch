class Api::V1::BeaconsController < Api::V1::BaseController
  def heartbeat
    sightings = Array(params[:beacons])
    updated   = 0
    unknown   = 0

    sightings.each do |s|
      beacon = Beacon.where(operator: current_tenant)
                     .find_by(uuid: s[:uuid].to_s, major: s[:major], minor: s[:minor])
      if beacon.nil?
        unknown += 1
        next
      end

      attrs = { last_seen_at: Time.current }
      attrs[:battery_pct] = s[:battery_pct].to_i if s[:battery_pct].present?
      beacon.update_columns(attrs)
      updated += 1
    end

    render json: { updated: updated, unknown: unknown }
  end
end
