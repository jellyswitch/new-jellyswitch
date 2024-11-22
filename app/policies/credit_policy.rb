
class CreditPolicy < ApplicationPolicy
  def enabled?
    location.credits_enabled?
  end

  def new?
    enabled?
  end

  def create?
    enabled?
  end

  def confirm?
    enabled?
  end
end