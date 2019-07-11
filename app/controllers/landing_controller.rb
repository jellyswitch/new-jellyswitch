# typed: true
class LandingController < ApplicationController
  def index
    if superadmin?
      redirect_to operators_path
    end
  end

  def welcome
    render :typeform, layout: false
  end
end
