class KisiUnlockJob < ApplicationJob
  queue_as :default

  # Performs the actual Kisi unlock out-of-band so the auto-unlock API can
  # respond optimistically (the member's tap doesn't wait on Kisi's 1-3s
  # round-trip). Reconciles the DoorPunch the controller created with
  # status: "pending" into "unlocked" or "failed".
  def perform(door_punch_id)
    ActsAsTenant.without_tenant do
      punch = DoorPunch.find_by(id: door_punch_id)
      return unless punch

      begin
        door = punch.door
        response = HTTParty.post(
          "https://api.kisi.io/locks/#{door.kisi_id}/unlock",
          headers: {
            "Authorization" => "KISI-LOGIN #{door.location.kisi_api_key}",
            "Content-type"  => "application/json",
            "Accept"        => "application/json",
          },
        )
        punch.update(
          status: response.success? ? "unlocked" : "failed",
          json:   response.parsed_response,
        )
      rescue => e
        Honeybadger.notify(e)
        punch.update(status: "failed")
      end
    end
  end
end
