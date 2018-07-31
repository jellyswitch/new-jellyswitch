class RoomPolicy < ApplicationPolicy
  def index?
    admin?
  end

  def show?
    admin_or_member?
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
    admin_or_member?
  end
end