class PostPolicy < ApplicationPolicy
  def index?
    can_see?
  end

  def new?
    can_see?
  end

  def create?
    can_see?
  end

  def show?
    can_see?
  end

  def enabled?
    # Nil-safe; see DoorPolicy#enabled? for the rationale.
    location&.bulletin_board_enabled? || false
  end

  def can_see?
    enabled? && (admin? || community_manager? || general_manager? || (user&.member_at_location?(location) && approved?))
  end
end
