class AutomatedWorkflowPolicy < ApplicationPolicy
  def index?
    admin? || general_manager? || superadmin?
  end

  def update?
    admin? || general_manager? || superadmin?
  end
end
