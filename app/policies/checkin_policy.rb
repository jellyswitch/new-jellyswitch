class CheckinPolicy < ApplicationPolicy
  def destroy?
    owner? || admin?
  end
end