class AnnouncementPolicy < ApplicationPolicy
  def index?
    enabled? && (staff? || member?)
  end

  def new?
    enabled? && staff?
  end

  def create?
    enabled? && staff?
  end

  def enabled?
    # Nil-safe; see DoorPolicy#enabled? for the rationale.
    location&.announcements_enabled? || false
  end

  private


  def can_see_announcements?
    staff? || member?
  end

  def staff?
    (admin? || community_manager? || general_manager?)
  end

  def member?
    (user.present? && user.allowed_in?(location) && approved?)
  end
end