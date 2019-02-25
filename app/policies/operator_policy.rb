class OperatorPolicy < ApplicationPolicy
  def index?
    superadmin?
  end

  def new?
    superadmin?
  end

  def show?
    superadmin?
  end

  def edit?
    superadmin?
  end

  def update?
    superadmin?
  end

  def create?
    superadmin?
  end

  def add_day_pass_product?
    superadmin?
  end
end