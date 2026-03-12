module Notifiable
  class FeedbackReply < Notifiable::Default
    private

    def create_feed_item
      # No feed item for replies — keep the thread private
    end

    def deep_link_data
      { type: "member_feedback", resource_id: member_feedback.id,
        path: "/member_feedbacks/#{member_feedback.id}" }
    end

    def should_send_notification?
      operator.member_feedback_notifications?
    end

    def message
      if from_admin?
        "You have a new reply from #{user.name}"
      else
        "New reply on member feedback"
      end
    end

    def recipients
      if from_admin?
        # Admin replied → notify the member who submitted the feedback
        [member_feedback.user]
      else
        # Member replied → notify location admins
        operator.users.relevant_admins_of_location(location)
      end
    end
  end
end
