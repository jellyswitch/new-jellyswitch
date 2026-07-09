
class Operator::MemberFeedbacksController < Operator::BaseController
  include LandingHelper # space_host_for — greeting seeding in #create

  def new
    @member_feedback = MemberFeedback.new
    authorize @member_feedback
    background_image
  end

  def create
    authorize MemberFeedback.new

    # Treat the conversation as ongoing: if the member already has a thread
    # for this location, append the new comment as a reply rather than
    # spinning up a fresh thread. New threads orphan staff replies that the
    # member never finds.
    existing = current_user.member_feedbacks
      .where(location: current_location)
      .order(updated_at: :desc)
      .first

    # Mirror the API path: the greeting thread is seeded at first-message
    # time (new members only), never on page view. See
    # Api::V1::MemberFeedbacksController#create.
    if existing.blank?
      seeded = MemberFeedback::EnsureHostGreeting.call(
        user: current_user,
        location: current_location,
        operator: current_tenant,
        host: space_host_for(current_location),
      )
      existing = seeded.member_feedback
    end

    if existing.present?
      result = MemberFeedback::CreateReply.call(
        member_feedback: existing,
        user: current_user,
        operator: current_tenant,
        body: member_feedback_params[:comment],
      )
      @member_feedback = existing
    else
      result = MemberFeedback::Create.call(
        member_feedback_params: member_feedback_params,
        user: current_user,
        operator: current_tenant,
        location: current_location,
      )
      @member_feedback = result.member_feedback
    end

    if result.success?
      flash[:success] = "Thank you — staff will reply right here."
      turbo_redirect(member_feedback_path(@member_feedback), action: restore_if_possible)
    else
      flash[:error] = result.message
      background_image
      render :new, status: 422
    end
  rescue Pundit::NotAuthorizedError, ActiveRecord::RecordNotFound
    raise
  rescue => e
    Honeybadger.notify(e)
    flash[:error] = "An error occurred: #{e.message}"
    turbo_redirect(referrer_or_root)
  end

  def index
    find_member_feedbacks
    authorize @member_feedbacks
    background_image
  end

  def show
    find_member_feedback
    authorize @member_feedback
    @feedback_replies = @member_feedback.feedback_replies.order(:created_at)
    @new_reply = FeedbackReply.new

    # Mark as read when the thread owner views it
    if @member_feedback.user_id == current_user.id
      @member_feedback.mark_as_read!
    end
  end

  def dismiss
    find_member_feedback
    authorize @member_feedback, :show?
    @member_feedback.update(dismissed_at: Time.current)
    @member_feedback.mark_as_read!

    respond_to do |format|
      # From the inbox: just pull the conversation's row out of the list.
      format.turbo_stream { render turbo_stream: turbo_stream.remove(@member_feedback) }
      format.html { turbo_redirect(member_feedbacks_path, action: restore_if_possible) }
    end
  end

  def reply
    find_member_feedback
    authorize @member_feedback, :reply?

    # Extract body from params — handle both scoped and unscoped form submissions
    body = params.dig(:feedback_reply, :body) || params[:body]

    if body.blank?
      flash[:error] = "Reply cannot be blank."
      turbo_redirect(member_feedback_path(@member_feedback), action: "replace")
      return
    end

    # Save the reply
    save_result = MemberFeedback::SaveReply.call(
      member_feedback: @member_feedback,
      user: current_user,
      operator: current_tenant,
      body: body
    )

    if save_result.success?
      # Send push notification separately — don't let failure affect the reply
      begin
        reply_record = save_result.feedback_reply
        is_admin = reply_record.from_admin?
        notif_enabled = current_tenant.member_feedback_notifications?
        has_cert = current_tenant.push_notification_certificate.attached?
        has_bundle = current_tenant.bundle_id.present?

        # Determine recipient
        if is_admin
          recipient = @member_feedback.user
        else
          recipient = current_tenant.users.relevant_admins_of_location(current_location).first
        end
        has_ios = recipient&.ios_token.present?
        has_android = recipient&.android_token.present?

        diag = "admin?=#{is_admin}, notif=#{notif_enabled}, cert=#{has_cert}, bundle=#{has_bundle}, recipient=#{recipient&.name}, ios=#{has_ios}, android=#{has_android}"
        Rails.logger.info("[FeedbackReply] DIAG: #{diag}")

        NotifiableFactory.for(reply_record).notify
        Rails.logger.info("[FeedbackReply] Notification sent successfully")
      rescue => e
        Rails.logger.error("FeedbackReply notification error: #{e.class}: #{e.message}")
        Honeybadger.notify(e)
      end
      turbo_redirect(member_feedback_path(@member_feedback), action: "replace")
    else
      flash[:error] = save_result.message
      turbo_redirect(member_feedback_path(@member_feedback), action: "replace")
    end
  rescue Pundit::NotAuthorizedError, ActiveRecord::RecordNotFound
    raise
  rescue => e
    Honeybadger.notify(e)
    flash[:error] = "An error occurred: #{e.message}"
    turbo_redirect(member_feedback_path(@member_feedback), action: "replace")
  end

  def my_feedback
    @member_feedbacks = MemberFeedback.where(user: current_user).order(updated_at: :desc)
    authorize @member_feedbacks
  end

  private

  def find_member_feedbacks
    # The admin conversations inbox: only threads the member actually engaged
    # in (excludes host-greeting-only threads), not dismissed, most recently
    # active first (updated_at bumps on every reply).
    @member_feedbacks = MemberFeedback.for_location(current_location)
                                      .with_member_message
                                      .not_dismissed
                                      .order("updated_at DESC")
  end

  def find_member_feedback(key=:id)
    # Try location-scoped first (for admins viewing all feedback),
    # then fall back to user's own feedback (for members viewing their threads).
    # Anonymous requests (expired sessions, link previews) have no fallback
    # scope — 404 rather than crash on current_user.
    @member_feedback = MemberFeedback.for_location(current_location).find_by(id: params[key])
    @member_feedback ||= current_user.member_feedbacks.find(params[key]) if current_user
    raise ActiveRecord::RecordNotFound if @member_feedback.nil?
  end

  def member_feedback_params
    params.require(:member_feedback).permit(:anonymous, :comment, :rating, :user_id)
  end
end
