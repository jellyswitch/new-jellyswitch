class LandingController < ApplicationController
  def index
    if member? 
      if approved?
        redirect_to home_path
      else
        redirect_to wait_path
      end
    end
    background_image
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
    if !logged_in?
      redirect_to root_path
    end
    if member? && approved?
      redirect_to home_path
    end
    background_image
  end
end
