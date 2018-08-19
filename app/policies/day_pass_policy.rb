class DayPassPolicy < ApplicationPolicy
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