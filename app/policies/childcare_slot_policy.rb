class ChildcareSlotPolicy < ApplicationPolicy
  def index?
    enabled? && admin?
  end

  def new?
    enabled? && admin?
  end

  def create?
    enabled? && admin?
  end

  def enabled?
    operator.childcare_enabled?
  end
end