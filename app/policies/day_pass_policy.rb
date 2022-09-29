
class DayPassPolicy < ApplicationPolicy
  def index?
    is_user? && billing_enabled?
  end

  def new?
    is_user? && billing_enabled?
  end

  def create?
    (is_user? && billing_enabled?) || admin? || community_manager? || general_manager?
  end

  def show?
    (owner? || admin? || community_manager? || general_manager?) && billing_enabled?
  end

  def code?
    is_user? && billing_enabled?
  end

  def redeem_code?
    is_user? && billing_enabled?
  end
end