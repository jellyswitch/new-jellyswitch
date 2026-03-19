class DiscountCodePolicy < ApplicationPolicy
  def index?
    (admin? || general_manager?) && billing_enabled?
  end

  def show?
    (admin? || general_manager?) && billing_enabled?
  end

  def new?
    (admin? || general_manager?) && billing_enabled?
  end

  def create?
    (admin? || general_manager?) && billing_enabled?
  end

  def edit?
    (admin? || general_manager?) && billing_enabled?
  end

  def update?
    (admin? || general_manager?) && billing_enabled?
  end

  def destroy?
    (admin? || general_manager?) && billing_enabled?
  end
end
