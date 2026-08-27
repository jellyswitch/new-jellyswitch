module Notifiable
  class FeedbackReply < Notifiable::Default
    def notify
      super
      send_email_fallback
    end

    private

    # A web/Concierge visitor has no app, so the push in send_notification
    # can't reach them — and the widget promised "the team will reach out."
    # Email the admin's reply when the member has no device tokens; app users
    # keep getting push only.
    def send_email_fallback
      return unless from_admin?
      return unless should_send_notification?

      member = member_feedback.user
      return if member.nil? || member.email.blank?
      return if member.ios_token.present? || member.android_token.present?

      FeedbackReplyMailer.with(reply: __getobj__).admin_reply.deliver_later
    end

    def create_feed_item
      # Admin → member replies stay private (they're a notification to the
      # member, not an action item for staff). But a member → staff reply IS
      # an action item: since the host-greeting thread now pre-exists for
      # everyone (MemberFeedback::EnsureHostGreeting), every real member
      # message arrives here as a reply rather than a new MemberFeedback — so
      # without this it never reaches the admin feed even though admins still
      # get the push. See Notifiable::MemberFeedback#create_feed_item for the
      # new-thread path; this mirrors it for the reply path.
      if from_admin?
        Rails.logger.info("[FeedbackReply] create_feed_item (no-op, admin reply)")
        return
      end

      blob = {
        type: "feedback",
        member_feedback_id: member_feedback.id,
        feedback_reply_id: id,
        # Stash the reply text so the feed card shows THIS message — the
        # parent MemberFeedback#comment is blank on greeting-first threads.
        body: body,
      }
      FeedItemCreator.upsert_feedback_feed_item(operator, location, user, blob, created_at: created_at)
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
