class Api::V1::Admin::FeedbacksController < Api::V1::Admin::BaseController
  def index
    # Sort by last activity (updated_at, bumped on every reply via
    # FeedbackReply touch: true) so the most recently active thread is first —
    # not by created_at, which is when the greeting shell was first created.
    feedbacks = MemberFeedback.where(operator: current_tenant)
      .not_dismissed
      .order(updated_at: :desc).limit(30)

    render json: feedbacks.map { |f| feedback_json(f) }
  end

  def show
    feedback = MemberFeedback.find(params[:id])

    replies = feedback.feedback_replies.includes(:user, :member_feedback)
      .order(:created_at).map { |r| reply_json(r) }

    render json: feedback_json(feedback).merge(replies: replies)
  end

  def reply
    feedback = MemberFeedback.find(params[:id])
    conflicts = nil
    reply = nil

    # Send-time collision check: the client may send last_seen_reply_id (the
    # highest staff-reply id it had loaded; null = it saw none). If the thread
    # gained a staff reply the sender hadn't seen, answer 409 with those
    # replies and save nothing — the second admin decides after reading the
    # first answer. Param absent entirely = legacy clients, no check. The row
    # lock makes two simultaneous sends serialize so both can't pass. The
    # guarantee is endpoint-local: other write paths (member API, web,
    # SaveReply interactor) don't take this lock; on human timescales they're
    # still caught because their replies commit before the sender's locked read.
    feedback.with_lock do
      conflicts = unseen_staff_replies(feedback) if params.key?(:last_seen_reply_id)

      if conflicts.blank?
        reply = feedback.feedback_replies.build(
          body: params[:body],
          user: current_api_user,
          operator: current_tenant,
        )
        reply.save
      end
    end

    if conflicts.present?
      render json: { conflicts: conflicts.map { |r| reply_json(r) } }, status: :conflict
    elsif reply.persisted?
      SendNotificationsJob.perform_later(reply)
      render json: reply_json(reply).merge(author: current_api_user.name, is_admin: true),
        status: :created
    else
      render_error(reply.errors.full_messages.join(', '))
    end
  end

  def dismiss
    feedback = MemberFeedback.find(params[:id])
    feedback.dismiss!
    render json: { success: true }
  end

  def restore
    feedback = MemberFeedback.find(params[:id])
    feedback.restore!
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

  # Staff replies the sender hadn't loaded when they hit Send. "Staff" mirrors
  # FeedbackReply#from_admin?: any author other than the thread's member. A
  # last_seen_reply_id that doesn't belong to this thread counts as saw-none.
  def unseen_staff_replies(feedback)
    # .to_s makes garbage param types (Hash/Array) deterministic: they
    # stringify to a non-numeric string, cast to 0 → saw-none (fail closed).
    last_seen_id = feedback.feedback_replies.find_by(id: params[:last_seen_reply_id].to_s)&.id || 0
    feedback.feedback_replies
      .includes(:user, :member_feedback)
      .where("feedback_replies.id > ?", last_seen_id)
      .where.not(user_id: feedback.user_id)
      .order(:id)
      .to_a
  end

  def reply_json(r)
    {
      id: r.id,
      body: r.body,
      author: r.user&.name,
      is_admin: r.from_admin?,
      created_at: r.created_at.iso8601,
    }
  end
end
