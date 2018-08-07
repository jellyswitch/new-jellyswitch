class LandingController < ApplicationController
  def index
    if logged_in?
      redirect_to users_path
    end
    background_image
  end
end
