class LandingController < ApplicationController
  def index
    background_image
    if admin?
      render :index
    else
      if member?
        if approved?
          redirect_to home_path
        else
          redirect_to wait_path
        end
      else
        render :index
      end
    end
  end

  def home
    background_image
    if member? || admin?
      if !approved? && !admin?
        redirect_to wait_path
      else
        render :home
      end
    else
      if logged_in?
        redirect_to new_subscription_path
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
end
