class OfficePolicy < ApplicationPolicy
  def show?
    true
  end
  
  def new?
    admin?
  end

  def create?
    admin?
  end

  def edit?
    admin?
  end

  def update?
    admin?
  end

  def day?
    admin? || (member? && approved?)
  end
end
