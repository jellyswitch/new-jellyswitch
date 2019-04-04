class Operator::LandingController < Operator::BaseController
  def index
    background_image
    if logged_in?
      if admin?
        redirect_to feed_items_path
      else
        if member?
          if approved?
            redirect_to home_path
          else
            redirect_to wait_path
          end
        else
          redirect_to choose_path
        end
      end
    end
  end

  def home
    background_image
    @doors = Door.all
    @member_feedback = MemberFeedback.new
    if member? || admin?
      if !approved? && !admin?
        redirect_to wait_path
      else
        render :home
      end
    else
      if logged_in?
        redirect_to choose_path
      else
        redirect_to root_path
      end
    end
  end

  def wait
    background_image
    if !logged_in?
      redirect_to root_path
    end
    if (member? && approved?) || admin?
      redirect_to home_path
    end
  end

  def choose
    background_image
    if !logged_in?
      redirect_to root_path
    else
      if (member? && approved?) || admin?
        redirect_to home_path
      end
    end
    @day_pass_types = current_tenant.day_pass_types.available.visible.order('amount_in_cents DESC')
    @plans = current_tenant.plans.for_individuals.order('amount_in_cents DESC')
  end

  def members_resources
    authorize :dashboard, :show?
    background_image
    @doors = Door.all
  end

  def privacy_policy
    background_image
  end
end
