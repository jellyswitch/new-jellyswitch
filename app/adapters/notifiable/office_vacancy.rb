module Notifiable
  # Pushed to operator admins when an office frees up and people are waiting.
  # This nudges staff to open the office queue and work it one person at a time
  # — it deliberately does NOT blast the waiting members. The wrapped record is
  # the freed Office (it responds to name / operator / location / id).
  class OfficeVacancy < Notifiable::Default
    def message
      "#{name} is available — #{waiting_count} #{'person'.pluralize(waiting_count)} waiting for an office. Notify them?"
    end

    def recipients
      operator.users.relevant_admins_of_location(location)
    end

    def should_send_notification?
      waiting_count.positive?
    end

    # Push only — no member-facing feed item (mirrors PointOfContactAlert).
    def create_feed_item; end

    def deep_link_data
      { type: "office_waitlist", resource_id: id, path: "/people/waitlist" }
    end

    def waiting_count
      @waiting_count ||= OfficeWaitlist.for(operator).demand[:waiting_count]
    end
  end
end
