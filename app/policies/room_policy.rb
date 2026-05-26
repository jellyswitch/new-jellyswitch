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
    enabled? && (admin? || general_manager?)
  end

  def create?
    enabled? && (admin? || general_manager?)
  end

  def edit?
    enabled? && (admin? || general_manager?)
  end

  def update?
    enabled? && (admin? || general_manager?)
  end

  def enabled?
    # Nil-safe; see DoorPolicy#enabled? for the rationale.
    location&.rooms_enabled? || false
  end

  def destroy?
    enabled? && user.superadmin?
  end
end
