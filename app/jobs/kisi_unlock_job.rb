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
        # Persistent client reuses the HTTPS connection so we don't pay the
        # TLS handshake on every unlock — see app/lib/kisi/client.rb.
        result = Kisi::Client.unlock(punch.door)
        punch.update(
          status: result[:success] ? "unlocked" : "failed",
          json:   result[:parsed] || result[:body],
        )
      rescue => e
        Honeybadger.notify(e)
        punch.update(status: "failed")
      end
    end
  end
end
