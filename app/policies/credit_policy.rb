# typed: true
class CreditPolicy < ApplicationPolicy
  def enabled?
    operator.credits_enabled?
  end
end