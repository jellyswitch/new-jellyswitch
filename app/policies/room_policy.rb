# typed: true
class RoomPolicy < ApplicationPolicy
  def index?
    is_user?
  end

  def show?
    if record.rentable?
      is_user?
    else
      admin? || (member? && approved?)
    end
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
end