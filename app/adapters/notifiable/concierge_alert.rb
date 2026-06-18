module Notifiable
  # Push to operator admins + the location's general/community managers when the
  # Concierge captures a lead it can't self-serve (day office / conference room /
  # office). Subject is the chat Activity. Push-only for V1 (the Person's Activity
  # timeline carries the full transcript; email can come later).
  class ConciergeAlert < Notifiable::Default
    def operator
      __getobj__.operator
    end

    private

    def create_feed_item
      # No-op — the captured Person's Activity timeline shows the chat in context.
    end

    def deep_link_data
      { type: "user", resource_id: __getobj__.user_id, path: "/users/#{__getobj__.user_id}" }
    end

    def should_send_notification?
      __getobj__.kind.to_s == "chat"
    end

    def message
      activity = __getobj__
      intent = activity.payload["intent"].to_s.tr("_", " ").strip
      label = intent.present? ? " (#{intent})" : ""
      "New chat lead: #{activity.user&.name}#{label}"
    end

    def recipients
      activity = __getobj__
      op = activity.operator
      location = activity.subject_type == "Location" ? activity.subject : nil

      admins = op.users.where(role: ::User::ADMIN)
      managers = if location
        op.users.where(
          role: [::User::GENERAL_MANAGER, ::User::COMMUNITY_MANAGER],
          current_location_id: location.id,
        )
      else
        ::User.none
      end

      (admins.to_a + managers.to_a).uniq
    end
  end
end
