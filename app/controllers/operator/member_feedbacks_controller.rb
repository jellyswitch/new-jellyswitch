
class Operator::MemberFeedbacksController < Operator::BaseController
  def new
    @member_feedback = MemberFeedback.new
    authorize @member_feedback
    background_image
  end

  def create
    authorize MemberFeedback.new
    result = MemberFeedback::Create.call(member_feedback_params: member_feedback_params, user: current_user, operator: current_tenant, location: current_location)
    @member_feedback = result.member_feedback

    if result.success?
      flash[:success] = "Thank you for your feedback!"
      turbo_redirect(home_path, action: restore_if_possible)
    else
      flash[:error] = result.message
      background_image
      render :new, status: 422
    end
  rescue Exception => e
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
    @member_feedback.mark_as_read!
    turbo_redirect(home_path, action: restore_if_possible)
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
        Rails.logger.info("[FeedbackReply] Sending notification for reply #{reply_record.id} from #{current_user.name} (admin?=#{reply_record.from_admin?})")
        NotifiableFactory.for(reply_record).notify
        Rails.logger.info("[FeedbackReply] Notification sent successfully")
        flash[:success] = "Reply sent."
      rescue => e
        Rails.logger.error("FeedbackReply notification error: #{e.class}: #{e.message}")
        Rails.logger.error(e.backtrace&.first(5)&.join("\n"))
        Honeybadger.notify(e)
        flash[:success] = "Reply sent (notification error logged)."
      end
      turbo_redirect(member_feedback_path(@member_feedback), action: "replace")
    else
      flash[:error] = save_result.message
      turbo_redirect(member_feedback_path(@member_feedback), action: "replace")
    end
  rescue Exception => e
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
    @member_feedbacks = MemberFeedback.for_location(current_location).order("created_at DESC").all
  end

  def find_member_feedback(key=:id)
    @member_feedback = MemberFeedback.for_location(current_location).find(params[key])
  end

  def member_feedback_params
    params.require(:member_feedback).permit(:anonymous, :comment, :rating, :user_id)
  end
end
