module Notifiable
  class DemandMiss < Notifiable::Default
    private

    def create_feed_item
      blob = { type: "demand-miss", demand_miss_id: id, user_name: user.name }
      FeedItemCreator.create_feed_item(operator, location, user, blob)
    end

    def should_send_notification?
      true
    end

    def message
      "#{user.name} couldn't find an available room"
    end

    def recipients
      operator.users.relevant_admins_of_location(location)
    end
  end
end
