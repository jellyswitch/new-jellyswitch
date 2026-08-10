module Notifiable
  # Shared date wording for the DayPass-wrapping Day Office adapters (ADR 0026).
  #
  # These notifications fire from paths with very different time horizons — a
  # walk-in burn is always today, but a reserve-time coverage burn or a
  # scheduled day can be weeks out — and they all read the same DayPass. So the
  # word "today" has to be earned from the pass's own day, judged in the
  # LOCATION's zone, never assumed from the fact that we're sending right now.
  module DayOfficeDayLabel
    private

    # "today", or "on Aug 14" / "Aug 14" depending on how the sentence reads.
    def day_label(prefix: "on ")
      tz = ActiveSupport::TimeZone[location&.time_zone.presence || "UTC"]
      return "today" if day == Time.current.in_time_zone(tz).to_date
      "#{prefix}#{day.strftime('%b %-d')}"
    end
  end
end
