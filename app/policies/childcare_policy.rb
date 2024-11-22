
class ChildcarePolicy < ApplicationPolicy
  def enabled?
    location.childcare_enabled?
  end
end