module Notifiable
  # Staff-facing alert for the BOOKING variant of an office-less Day Office
  # burn (ADR 0026): the member spent a Day Office bundle pass covering a room
  # reservation, so the day is paid for but the pool had nothing free. Nobody
  # has arrived — the date may be weeks out — so the copy carries the date and
  # avoids the walk-in's "arrived", which would send staff looking for someone
  # who isn't in the building.
  #
  # Everything else (audience, deep link, ungated delivery, no feed item) is
  # inherited from the walk-in alert.
  class DayOfficeUnassignedBookingAlert < Notifiable::DayOfficeUnassignedAlert
    private

    def message
      "#{member_name} booked a Day Office for #{day_label(prefix: '')} but no office " \
        "was free — reassign a room or restore the pass"
    end
  end
end
