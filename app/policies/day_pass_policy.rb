class DayPassPolicy < ApplicationPolicy
  def index?
    admin?
  end

  def new?
    is_user? && !member?
  end

  def create?
    is_user? && !member?
  end

  def show?
    owner? || admin?
  end
end