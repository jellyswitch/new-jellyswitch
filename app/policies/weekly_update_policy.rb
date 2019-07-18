# typed: true
class WeeklyUpdatePolicy < ApplicationPolicy
  def index?
    admin?
  end

  def create?
    admin?
  end

  def show?
    admin?
  end

  def new?
    superadmin?
  end
end