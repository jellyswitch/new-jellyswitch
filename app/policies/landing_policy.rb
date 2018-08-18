class LandingPolicy < ApplicationPolicy
  def home?
    admin_or_member?
  end
end