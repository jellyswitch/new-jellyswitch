module Notifiable
  class DailyDigest < Notifiable::Default
    private

    def create_feed_item
      # Feed item already created by the job, skip
    end

    def should_send_notification?
      true
    end

    def message
      dp = blob["day_pass_count"].to_i
      res = blob["reservation_count"].to_i
      paid = blob["paid_reservation_count"].to_i
      revenue = blob["total_revenue_cents"].to_i / 100.0

      parts = []
      parts << "#{dp} day #{dp == 1 ? 'pass' : 'passes'}" if dp > 0
      parts << "#{res} #{res == 1 ? 'reservation' : 'reservations'}" if res > 0

      msg = "Today: #{parts.join(', ')}"
      msg += " ($#{'%.2f' % revenue} in paid bookings)" if revenue > 0
      msg
    end

    def recipients
      operator.users.relevant_admins_of_location(location)
    end
  end
end
