class LandingController < ApplicationController
  before_action :ensure_subscribed, except: [:index, :wait]

  def index
    if member? && approved?
      redirect_to home_path
    end
    background_image
  end

  def home
    background_image
  end

  def wait
    if member? && approved?
      redirect_to home_path
    end
    background_image
  end
end
