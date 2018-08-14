class LandingController < ApplicationController
  before_action :ensure_subscribed, except: [:index]

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
