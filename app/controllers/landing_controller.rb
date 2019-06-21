# typed: true
class LandingController < ApplicationController
  def index
    if superadmin?
      redirect_to operators_path
    end
  end
end