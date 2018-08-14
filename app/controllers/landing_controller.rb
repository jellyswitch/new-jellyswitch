class LandingController < ApplicationController
  def index
    if logged_in?
      redirect_to home_path
    end
    background_image
  end

  def home
    if !logged_in?
      redirect_to root_path
    end
    background_image
  end
end
