# typed: true
class DayPassTypePolicy < ApplicationPolicy
  def index?
    (admin? && billing_enabled? || community_manager? || general_manager?)
  end

  def show?
    (admin? && billing_enabled? || community_manager? || general_manager?)
  end

  def edit?
    (admin? && billing_enabled? || community_manager? || general_manager?)
  end

  def new?
    (admin? && billing_enabled? || community_manager? || general_manager?)
  end

  def create?
    (admin? && billing_enabled? || community_manager? || general_manager?)
  end

  def update?
    (admin? && billing_enabled? || community_manager? || general_manager?)
  end

  def destroy?
    (admin? && billing_enabled? || community_manager? || general_manager?)
  end
end