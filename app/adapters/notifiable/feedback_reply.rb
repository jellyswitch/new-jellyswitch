module Notifiable
  class FeedbackReply < Notifiable::Default
    private

    def create_feed_item
      # No feed item for replies — keep the thread private
      Rails.logger.info("[FeedbackReply] create_feed_item (no-op)")
    end

    def deep_link_data
      { type: "member_feedback", resource_id: member_feedback.id,
        path: "/member_feedbacks/#{member_feedback.id}" }
    end

    def should_send_notification?
      result = operator.member_feedback_notifications?
      Rails.logger.info("[FeedbackReply] should_send_notification? => #{result}")
      result
    end

    def message
      msg = if from_admin?
        "You have a new reply from #{user.name}"
      else
        "New reply on member feedback"
      end
      Rails.logger.info("[FeedbackReply] message => #{msg}")
      msg
    end

    def recipients
      recips = if from_admin?
        # Admin replied → notify the member who submitted the feedback
        [member_feedback.user]
      else
        # Member replied → notify location admins
        operator.users.relevant_admins_of_location(location)
      end
      Rails.logger.info("[FeedbackReply] recipients => #{recips.map(&:name)} (#{recips.count} total), from_admin?=#{from_admin?}")
      recips.each do |r|
        Rails.logger.info("[FeedbackReply]   - #{r.name}: ios_token=#{r.ios_token.present?}, android_token=#{r.android_token.present?}")
      end
      recips
    end
  end
end
