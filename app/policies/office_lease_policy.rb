class OfficeLeasePolicy < ApplicationPolicy
  def index?
    admin?
  end

  def show?
    admin? || record.organization.owner == user
  end

  def new?
    admin?
  end

  def create?
    admin?
  end

  def destroy?
    admin?
  end
end
