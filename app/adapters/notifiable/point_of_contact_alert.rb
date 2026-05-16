module Notifiable
  # Sends a push notification to the Person's point_of_contact when a
  # significant Activity is logged for them. No FeedItem is written —
  # the Person's Activity timeline already shows the event in context;
  # this adapter is for direct alerts to the relationship owner.
  class PointOfContactAlert < Notifiable::Default
    SIGNIFICANT_KINDS = %w[signup email_replied subscription_ended].freeze

    def operator
      __getobj__.operator
    end

    private

    def create_feed_item
      # No-op — handled by the Person's Activity timeline.
    end

    def deep_link_data
      { type: "user", resource_id: __getobj__.user_id, path: "/users/#{__getobj__.user_id}" }
    end

    def should_send_notification?
      __getobj__.user&.point_of_contact_id.present? &&
        SIGNIFICANT_KINDS.include?(__getobj__.kind.to_s)
    end

    def message
      activity = __getobj__
      person = activity.user
      case activity.kind.to_s
      when "signup"
        "New signup: #{person&.name || 'a Person'}"
      when "email_replied"
        "#{person&.name || 'A Person'} replied to your email"
      when "subscription_ended"
        "#{person&.name || 'A Person'}'s membership ended"
      else
        "Activity update for #{person&.name || 'a Person'}"
      end
    end

    def recipients
      poc = __getobj__.user&.point_of_contact
      poc ? [poc] : []
    end
  end
end
