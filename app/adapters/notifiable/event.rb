module Notifiable
  # Pushes a member-proposed event to the relevant admins for review.
  # Only fires for pending events — admin / GM / manager submissions are
  # auto-approved (see Events::Create) and don't need this round-trip.
  class Event < Notifiable::Default
    private

    def create_feed_item
      blob = {
        type:     "event-proposed",
        event_id: id,
        title:    title,
      }
      FeedItemCreator.create_feed_item(operator, location, user, blob, created_at: created_at)
    end

    def deep_link_data
      { type: "event", resource_id: id, path: "/events/#{id}" }
    end

    def should_send_notification?
      # Reuse the same operator-level toggle that gates member-feedback
      # pushes — admins who muted member-feedback alerts didn't sign up
      # for separate event-pending alerts either, and there isn't a
      # dedicated event_notifications? column to lean on.
      operator.member_feedback_notifications?
    end

    def message
      "#{user.name} proposed an event: #{title}"
    end

    def recipients
      operator.users.relevant_admins_of_location(location)
    end
  end
end
