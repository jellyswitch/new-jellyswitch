class Operator::LandingController < Operator::ApplicationController
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
  end
end
