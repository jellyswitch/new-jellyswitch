
class RoomPolicy < ApplicationPolicy
  def index?
    enabled? && is_user?
  end

  def show?
    enabled? && if record.rentable?
      is_user?
    else
      (admin? || community_manager? || general_manager? || (user.allowed_in?(location) && approved?))
    end
  end

  def new?
    enabled? && (admin? || community_manager? || general_manager?)
  end

  def create?
    enabled? && (admin? || community_manager? || general_manager?)
  end

  def edit?
    enabled? && (admin? || community_manager? || general_manager?)
  end

  def update?
    enabled? && (admin? || community_manager? || general_manager?)
  end

  def enabled?
    operator.rooms_enabled?
  end
end