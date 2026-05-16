class Api::V1::Admin::FeedbacksController < Api::V1::Admin::BaseController
  def index
    feedbacks = MemberFeedback.where(operator: current_tenant)
      .order(created_at: :desc).limit(30)

    render json: feedbacks.map { |f| feedback_json(f) }
  end

  def show
    feedback = MemberFeedback.find(params[:id])

    replies = feedback.feedback_replies.order(:created_at).map { |r|
      {
        id: r.id,
        body: r.body,
        author: r.user&.name,
        is_admin: r.from_admin?,
        created_at: r.created_at.iso8601,
      }
    }

    render json: feedback_json(feedback).merge(replies: replies)
  end

  def reply
    feedback = MemberFeedback.find(params[:id])
    reply = feedback.feedback_replies.build(
      body: params[:body],
      user: current_api_user,
      operator: current_tenant,
    )

    if reply.save
      SendNotificationsJob.perform_later(reply)
      render json: {
        id: reply.id,
        body: reply.body,
        author: current_api_user.name,
        is_admin: true,
        created_at: reply.created_at.iso8601,
      }, status: :created
    else
      render_error(reply.errors.full_messages.join(', '))
    end
  end

  def dismiss
    feedback = MemberFeedback.find(params[:id])
    feedback.mark_as_read!
    render json: { success: true }
  end

  private

  def feedback_json(f)
    {
      id: f.id,
      body: f.comment,
      user_name: f.anonymous? ? "Anonymous" : f.user&.name,
      rating: f.rating,
      reply_count: f.feedback_replies.count,
      read_by_admin: f.last_read_at.present?,
      created_at: f.created_at.iso8601,
    }
  end
end
