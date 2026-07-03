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
        # `FeedbackReply#from_admin?` matches the admin-side controller and
        # `admin_or_manager?(location)` — i.e. admin OR superadmin OR
        # general-manager OR community-manager. The prior `r.user&.admin?`
        # only matched `role == ADMIN || admin == true`, so a reply from
        # a GM or CM rendered without the "Staff" badge on the member's
        # mobile thread.
        is_admin: r.from_admin?,
        created_at: r.created_at.strftime("%B %e at %l:%M %p"),
      }
    }

    feedback.update(last_read_at: Time.current) if feedback.last_read_at.nil?

    render json: feedback_json(feedback).merge(replies: replies)
  end

  def create
    # Treat the conversation as ongoing: if the member already has a thread
    # for this location (typically the auto-generated host-greeting created
    # by MemberFeedback::EnsureHostGreeting on first dashboard view), append
    # the new comment as a reply rather than spinning up a parallel
    # MemberFeedback. The parallel-thread bug stranded the staff reply on
    # the original (host-greeting) thread while the member's question was
    # filed in a brand-new thread that nobody was watching — and showed up
    # in the mobile inbox as two separate cards ("Open" and "Replied").
    #
    # Mirrors the same logic already in
    # Operator::MemberFeedbacksController#create; the API path was missed
    # when that fix landed.
    existing = current_api_user.member_feedbacks
      .where(location: current_location)
      .order(updated_at: :desc)
      .first

    if existing.present?
      result = MemberFeedback::CreateReply.call(
        member_feedback: existing,
        user: current_api_user,
        operator: current_tenant,
        body: params[:body],
      )

      if result.success?
        render json: feedback_json(existing.reload), status: :created
      else
        render_error(result.message)
      end
    else
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
  end

  def reply
    feedback = current_api_user.member_feedbacks.find(params[:id])

    # Route through CreateReply (SaveReply + CreateNotifications) — the same
    # organizer #create already uses — instead of a bare reply.save. The old
    # path saved the reply but fired NO notification pipeline, so an in-thread
    # follow-up (MessageDetailScreen → feedbackAPI.reply) reached neither the
    # admins' push NOR the management-feed card: a real member's "I booked a
    # room but it's not showing" sat unanswered because nobody was alerted.
    result = MemberFeedback::CreateReply.call(
      member_feedback: feedback,
      user: current_api_user,
      operator: current_tenant,
      body: params[:body],
    )

    if result.success?
      reply = result.feedback_reply
      render json: {
        id: reply.id,
        body: reply.body,
        author: current_api_user.name,
        created_at: reply.created_at.strftime("%B %e at %l:%M %p"),
      }, status: :created
    else
      render_error(result.message)
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
    # Use the same `can_rate?` rule that gates the UI, so a client can't
    # bypass the 24h-wrap-up window by hitting the API directly. The mobile
    # app only shows the rating affordance when `can_rate` is true, but the
    # server is the source of truth.
    return render_error('Conversation is still active — please wait before rating') unless feedback.can_rate?

    feedback.update!(rating: rating)
    render json: feedback_json(feedback)
  end

  private

  def feedback_json(f)
    {
      id: f.id,
      body: f.comment,
      rating: f.rating,
      status: f.feedback_replies.any? ? 'replied' : 'open',
      reply_count: f.feedback_replies.count,
      unread: f.last_read_at.nil?,
      created_at: f.created_at.strftime("%B %e, %Y"),
      # Mobile uses this to show the "rate this experience" CTA. The rule
      # (staff has replied AND conversation has been silent for 24h AND
      # not yet rated) lives on the model so the API and the model-level
      # rate guard agree. See MemberFeedback#can_rate? for the full logic.
      can_rate: f.can_rate?,
    }
  end
end
