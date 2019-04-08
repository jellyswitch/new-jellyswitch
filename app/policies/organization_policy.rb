class OrganizationPolicy < ApplicationPolicy
  def index?
    admin?
  end

  def show?
    admin? || user.organization_owner?
  end

  def new?
    admin?
  end

  def create?
    admin?
  end

  def edit?
    admin? || user.organization_owner?
  end

  def update?
    admin?
  end

  def destroy?
    admin?
  end
end
