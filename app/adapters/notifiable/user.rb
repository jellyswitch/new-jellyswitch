module Notifiable
  class User < Notifiable::Default
    private

    def create_feed_item
      # Idempotent: skip if a new-user FeedItem already exists for this user.
      # SendNotificationsJob is invoked both on signup AND on admin approval,
      # which previously produced two "X signed up" rows on the dashboard for
      # the same person. Approval should still send the push/email — only the
      # duplicate feed entry is suppressed.
      return if FeedItem.where(user_id: id, operator_id: operator.id)
                        .where("blob->>'type' = ?", "new-user")
                        .exists?
      blob = { type: "new-user" }
      FeedItemCreator.create_feed_item(operator, location, self.__getobj__, blob)
    end

    def deep_link_data
      { type: "user", resource_id: id, path: "/users/#{id}" }
    end

    def should_send_notification?
      operator.signup_notifications?
    end

    def message
      "New user signup: #{name}"
    end

    def recipients
      operator.users.relevant_admins_of_location(location)
    end
  end
end
