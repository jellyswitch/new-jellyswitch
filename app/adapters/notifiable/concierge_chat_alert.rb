module Notifiable
  # Push to operator admins + the location's managers when a visitor starts a
  # LIVE chat during business hours, so a staffer can jump in. Wraps a
  # ConciergeConversation. Push-only (the inbox is the surface to reply).
  class ConciergeChatAlert < Notifiable::Default
    def operator
      __getobj__.operator
    end

    private

    def create_feed_item; end

    def deep_link_data
      { type: "concierge_conversation", resource_id: __getobj__.id,
        path: "/concierge/conversations/#{__getobj__.id}" }
    end

    def should_send_notification?
      true
    end

    def message
      loc = __getobj__.location&.name
      loc.present? ? "💬 Someone's chatting on your site (#{loc})" : "💬 Someone's chatting on your site"
    end

    def recipients
      convo = __getobj__
      op = convo.operator
      location = convo.location

      admins = op.users.where(role: ::User::ADMIN)
      managers = if location
        op.users.where(role: [::User::GENERAL_MANAGER, ::User::COMMUNITY_MANAGER],
                       current_location_id: location.id)
      else
        ::User.none
      end

      (admins.to_a + managers.to_a).uniq
    end
  end
end
