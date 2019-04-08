class OfficeLeasePolicy < ApplicationPolicy
  def index
    admin?
  end

  def new
    admin?
  end

  def create
    admin?
  end
end
