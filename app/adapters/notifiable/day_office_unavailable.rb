module Notifiable
  # Member-facing push when a Day Office burn found no free room (ADR 0026,
  # decision #4). Fires from two paths with different horizons: a walk-in door
  # burn (always today) and a reserve-time coverage burn (a booking that can be
  # weeks out). The day label comes from the PASS, so a future-dated booking
  # says "on Aug 14" rather than a "today" that would be plainly wrong.
  #
  # Either way access is real and only the office is missing, so the copy
  # reassures and routes them to staff, who can reassign a room or restore the
  # pass. Wraps the DayPass.
  class DayOfficeUnavailable < Notifiable::Default
    include Notifiable::DayOfficeDayLabel

    private

    def create_feed_item; end

    def deep_link_data
      { type: "day_pass", resource_id: id, path: "/day_passes/#{id}" }
    end

    def should_send_notification?
      true
    end

    def message
      "No offices are left #{day_label} — your pass still works; see staff."
    end

    def recipients
      [user].compact
    end
  end
end
