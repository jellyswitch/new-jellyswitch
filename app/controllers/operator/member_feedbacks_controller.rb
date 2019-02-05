class Operator::MemberFeedbacksController < Operator::ApplicationController
  def new
    @member_feedback = MemberFeedback.new
    authorize @member_feedback
    background_image
  end

  def create
    authorize MemberFeedback.new
    result = CreateMemberFeedback.call(member_feedpack_params: member_feedpack_params, user: current_user, operator: current_tenant)
    @member_feedback = result.member_feedback
    
    if result.success?
      flash[:success] = "Your feedback has been submitted."
      redirect_to root_path
    else
      flash[:error] = result.message
      background_image
      render :new
    end
  end

  def index
    find_member_feedbacks
    authorize @member_feedbacks
    background_image
  end

  def show
    find_member_feedback
    authorize @member_feedback
  end

  private

  def find_member_feedbacks
    @member_feedbacks = MemberFeedback.order("created_at DESC").all
  end

  def find_member_feedback(key=:id)
    @member_feedback = MemberFeedback.find(params[key])
  end

  def member_feedpack_params
    params.require(:member_feedback).permit(:anonymous, :comment, :rating, :user_id)
  end
end