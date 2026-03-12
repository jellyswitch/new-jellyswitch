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

    # Touch the parent so updated_at sorts correctly
    context.member_feedback.touch

    context.notifiable = reply
  end
end
