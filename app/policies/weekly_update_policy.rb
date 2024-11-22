
class WeeklyUpdatePolicy < ApplicationPolicy
  def index?
    (admin? || general_manager?)
  end

  def create?
    (admin? || general_manager?)
  end

  def show?
    (admin? || general_manager?)
  end

  def new?
    user.id == User.first.id # only dave can do this
  end
end