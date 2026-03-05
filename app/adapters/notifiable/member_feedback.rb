module Notifiable
  class MemberFeedback < Notifiable::Default
    private

    def create_feed_item
      blob = {type: "feedback", member_feedback_id: id}
      FeedItemCreator.create_feed_item(operator, location, user, blob, created_at: created_at)
    end

    def deep_link_data
      { type: "member_feedback", resource_id: id, path: "/member_feedbacks/#{id}" }
    end

    def should_send_notification?
      operator.member_feedback_notifications?
    end

    def message
      "New member feedback"
    end

    def recipients
      operator.users.relevant_admins_of_location(location)
    end
  end
end
