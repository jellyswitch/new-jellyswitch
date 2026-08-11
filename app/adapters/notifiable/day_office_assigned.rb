module Notifiable
  # Member-facing push naming the office a Day Office pass just got (ADR 0026)
  # — the push counterpart of UserMailer#day_office_confirmation. Wraps the
  # DayPass; the room and window are read off its LIVE office_hold, which the
  # job re-queries when it deserializes the pass. If the hold was released
  # between enqueue and run (refund, reschedule, admin restore) there is
  # nothing true left to say, so the push is suppressed rather than announcing
  # a room the member no longer holds.
  class DayOfficeAssigned < Notifiable::Default
    include Notifiable::DayOfficeDayLabel

    private

    # No feed item. The purchase already posts its own "bought a day pass"
    # card (Notifiable::DayPass), a bundle burn is deliberately silent, and a
    # day-office hold is excluded from the reservation timeline (ADR 0026).
    def create_feed_item; end

    def deep_link_data
      { type: "day_pass", resource_id: id, path: "/day_passes/#{id}" }
    end

    def should_send_notification?
      hold.present?
    end

    # Default#notify logs (and validates) the message BEFORE it consults
    # should_send_notification?, so this must stay safe on the released-hold
    # path — where the placeholder is only ever written to the log.
    def message
      return "Day Office hold is no longer active" if hold.nil?
      "🔑 #{hold.room.name} is yours #{day_label}, #{hold.window_label}"
    end

    def recipients
      [user].compact
    end

    def hold
      return @hold if defined?(@hold)
      @hold = office_hold
    end
  end
end
