class Api::V1::MemberFeedbacksController < Api::V1::BaseController
  def index
    feedbacks = current_api_user.member_feedbacks
      .where(operator: current_tenant)
      .order(created_at: :desc)
      .limit(20)

    render json: feedbacks.map { |f| feedback_json(f) }
  end

  def show
    feedback = current_api_user.member_feedbacks.find(params[:id])
    replies = feedback.feedback_replies.order(:created_at).map { |r|
      {
        id: r.id,
        body: r.body,
        author: r.user&.name,
        is_admin: r.user&.admin?,
        created_at: r.created_at.strftime("%B %e at %l:%M %p"),
      }
    }

    feedback.update(last_read_at: Time.current) if feedback.last_read_at.nil?

    render json: feedback_json(feedback).merge(replies: replies)
  end

  def create
    feedback = MemberFeedback.new(
      comment: params[:body],
      rating: params[:rating],
      user: current_api_user,
      operator: current_tenant,
      location: current_location,
    )

    if feedback.save
      CreateNotificationsAsync.call(notifiable: feedback)
      render json: feedback_json(feedback), status: :created
    else
      render_error(feedback.errors.full_messages.first)
    end
  end

  def reply
    feedback = current_api_user.member_feedbacks.find(params[:id])
    reply = feedback.feedback_replies.build(
      body: params[:body],
      user: current_api_user,
      operator: current_tenant,
    )

    if reply.save
      render json: {
        id: reply.id,
        body: reply.body,
        author: current_api_user.name,
        created_at: reply.created_at.strftime("%B %e at %l:%M %p"),
      }, status: :created
    else
      render_error(reply.errors.full_messages.first)
    end
  end

  # PATCH /api/v1/member_feedbacks/:id/rate
  # Members rate the customer-service experience after staff has
  # replied — not at message-send time, when they have nothing to
  # judge yet. Body: { rating: 1..5 }.
  def rate
    feedback = current_api_user.member_feedbacks.find(params[:id])
    rating = params[:rating].to_i
    return render_error('Rating must be 1–5') unless (1..5).include?(rating)
    return render_error('No staff reply yet — nothing to rate') unless feedback.feedback_replies.any? { |r| r.user&.admin? }

    feedback.update!(rating: rating)
    render json: feedback_json(feedback)
  end

  private

  def feedback_json(f)
    has_admin_reply = f.feedback_replies.any? { |r| r.user&.admin? }
    {
      id: f.id,
      body: f.comment,
      rating: f.rating,
      status: f.feedback_replies.any? ? 'replied' : 'open',
      reply_count: f.feedback_replies.count,
      unread: f.last_read_at.nil?,
      created_at: f.created_at.strftime("%B %e, %Y"),
      # Mobile uses this to show the "rate this experience" CTA only
      # once there's actually been a staff reply to rate.
      can_rate: has_admin_reply && f.rating.blank?,
    }
  end
end
