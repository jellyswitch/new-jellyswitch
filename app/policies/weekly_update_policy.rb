# typed: true
class WeeklyUpdatePolicy < ApplicationPolicy
  def index?
    admin? || community_manager? || general_manager?
  end

  def create?
    admin? || community_manager? || general_manager?
  end

  def show?
    admin? || community_manager? || general_manager?
  end

  def new?
    user.id == User.first.id # only dave can do this
  end
end