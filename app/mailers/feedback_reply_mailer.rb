class FeedbackReplyMailer < ApplicationMailer
  # Emails an admin's Feedback reply to the member when a push can't reach
  # them (no app tokens) — the path web/Concierge visitors take: the widget
  # promised "the team will reach out," and without this the reply only ever
  # went out as a push their nonexistent app never saw. Reply-To is the
  # replying admin so the visitor can answer the email directly.
  def admin_reply
    @reply    = params[:reply]
    @user     = @reply.member_feedback.user
    @operator = @reply.member_feedback.operator
    @author   = @reply.user

    mail(
      to: @user.email,
      from: @operator.sender_from_address,
      reply_to: @author&.email.presence,
      subject: "Reply from #{@operator.name}",
    )
  end
end
