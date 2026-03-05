module Events::TimeParsing
  private

  # Parses a datetime string (from the form) in the context of the given
  # timezone, correctly handling DST for the *event's* date rather than
  # the current date.
  def parse_time_in_zone(time_string, time_zone_name)
    zone = ActiveSupport::TimeZone[time_zone_name]
    zone.strptime(time_string, "%m/%d/%Y %l:%M %p")
  end
end
