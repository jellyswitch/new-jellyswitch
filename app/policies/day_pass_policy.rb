# typed: true
class DayPassPolicy < ApplicationPolicy
  def index?
    admin?
  end

  def new?
    is_user?
  end

  def create?
    is_user? || admin?
  end

  def show?
    owner? || admin?
  end

  def code?
    is_user?
  end

  def redeem_code?
    is_user?
  end
end