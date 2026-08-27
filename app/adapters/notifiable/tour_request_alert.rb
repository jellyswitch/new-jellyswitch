module Notifiable
  # Push (and via Task 11 also email) to operator admins + the
  # requested location's general/community managers when a new tour
  # request comes in via the embed widget. Subject is the Activity.
  class TourRequestAlert < Notifiable::Default
    def operator
      __getobj__.operator
    end

    def notify
      super
      send_email
      send_visitor_confirmation
    end

    private

    def create_feed_item
      # No-op — the Person's Activity timeline shows the request in context.
    end

    def deep_link_data
      { type: "user", resource_id: __getobj__.user_id, path: "/users/#{__getobj__.user_id}" }
    end

    def should_send_notification?
      __getobj__.kind.to_s == "tour_request"
    end

    def message
      activity = __getobj__
      person = activity.user
      preview = activity.payload["message"].to_s.truncate(40)
      preview.present? ? "New tour request: #{person&.name} — #{preview}" : "New tour request: #{person&.name}"
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
        # `::User` (not bare `User`) — lexical lookup from inside
        # Notifiable::TourRequestAlert otherwise resolves to Notifiable::User,
        # the adapter sibling, which has no .none scope.
        ::User.none
      end

      (admins.to_a + managers.to_a).uniq
    end

    def send_visitor_confirmation
      return unless should_send_notification?
      requester = __getobj__.user
      return if requester.nil? || requester.email.blank?

      TourRequestMailer.with(activity: __getobj__).confirmation.deliver_later
    end

    def send_email
      return unless should_send_notification?
      recipients.each do |recipient|
        TourRequestMailer
          .with(recipient: recipient, activity: __getobj__)
          .new_request
          .deliver_later
      end
    end
  end
end
