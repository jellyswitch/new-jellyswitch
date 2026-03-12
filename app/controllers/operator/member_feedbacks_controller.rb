
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
  end

  def reply
    find_member_feedback
    authorize @member_feedback, :reply?

    result = MemberFeedback::CreateReply.call(
      member_feedback: @member_feedback,
      user: current_user,
      operator: current_tenant,
      body: params[:feedback_reply][:body]
    )

    if result.success?
      turbo_redirect(member_feedback_path(@member_feedback), action: "replace")
    else
      flash[:error] = result.message
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
