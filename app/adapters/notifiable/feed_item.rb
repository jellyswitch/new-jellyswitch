module Notifiable
  class FeedItem < Notifiable::Default
    def create_feed_item
    end

    def deep_link_data
      { type: "feed_item", resource_id: id, path: "/feed_items/#{id}" }
    end

    def should_send_notification?
      if blob&.dig("type") == "daily-digest"
        true
      else
        operator.post_notifications?
      end
    end

    def message
      if blob&.dig("type") == "daily-digest"
        dp = blob["day_pass_count"].to_i
        res = blob["reservation_count"].to_i
        revenue = blob["total_revenue_cents"].to_i / 100.0

        parts = []
        parts << "#{dp} day #{dp == 1 ? 'pass' : 'passes'}" if dp > 0
        parts << "#{res} #{res == 1 ? 'reservation' : 'reservations'}" if res > 0
        msg = "Today: #{parts.join(', ')}"
        msg += " ($#{'%.2f' % revenue} in paid bookings)" if revenue > 0
        msg
      else
        "#{user.name} has posted a new management note"
      end
    end

    def recipients
      operator.users.relevant_admins_of_location(location)
    end
  end
end
