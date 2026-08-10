module Notifiable
  # Member-facing push when staff move a Day Office pass to a different room
  # (Task 12). Wraps the HOLD reservation, not the pass — the hold is what
  # changed, and the pass id is reachable from it for the deep link. A hold
  # cancelled between enqueue and run fails GlobalID deserialization
  # (Reservation's default_scope hides cancelled rows) and SendNotificationsJob
  # discards the job quietly, which is the behaviour we want.
  class DayOfficeReassigned < Notifiable::Default
    private

    def create_feed_item; end

    def deep_link_data
      { type: "day_pass", resource_id: day_office_pass_id, path: "/day_passes/#{day_office_pass_id}" }
    end

    def should_send_notification?
      true
    end

    def message
      "Your office for #{day_label} is now #{room.name}"
    end

    def recipients
      [user].compact
    end

    # datetime_in's reader already presents the room's location zone, so the
    # date here is the local one; "today" is judged in that same zone.
    def day_label
      tz = ActiveSupport::TimeZone[location&.time_zone.presence || "UTC"]
      day = datetime_in.to_date
      day == Time.current.in_time_zone(tz).to_date ? "today" : day.strftime("%b %-d")
    end
  end
end
