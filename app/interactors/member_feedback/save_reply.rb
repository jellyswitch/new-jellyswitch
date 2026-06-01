class MemberFeedback::SaveReply
  include Interactor

  def call
    reply = FeedbackReply.new(
      member_feedback: context.member_feedback,
      user: context.user,
      operator: context.operator,
      body: context.body
    )

    context.feedback_reply = reply

    if !reply.save
      context.fail!(message: "Could not save reply.")
    end

    # Parent updated_at is bumped automatically by FeedbackReply's
    # `belongs_to :member_feedback, touch: true`, so the inboxes sort by
    # last activity. No explicit touch needed here.

    context.notifiable = reply
  end
end
