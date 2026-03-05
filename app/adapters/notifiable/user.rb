module Notifiable
  class User < Notifiable::Default
    private

    def create_feed_item
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
