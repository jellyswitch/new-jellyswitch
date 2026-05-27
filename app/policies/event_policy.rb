
class EventPolicy < ApplicationPolicy
  def index?
    enabled?
  end

  def past?
    enabled?
  end

  def new?
    enabled? && can_submit?
  end

  def create?
    enabled? && can_submit?
  end

  # Members + office-lease holders can propose events on the web now,
  # mirroring the existing mobile API path (Api::V1::EventsController#create).
  # Non-admin submissions land with approved_at=nil and go through the same
  # approval queue admins already use for mobile member submissions.
  # Anonymous / day-pass-only / pending users still can't submit.
  def can_submit?
    return false unless is_user?
    admin? || community_manager? || general_manager? || superadmin? ||
      user.has_active_subscription? ||
      (location.present? && user.has_active_lease?(location))
  end

  def show?
    enabled?
  end

  def edit?
    enabled? && (admin? || community_manager? || general_manager?)
  end

  def update?
    enabled? && (admin? || community_manager? || general_manager?)
  end

  def destroy?
    enabled? && (admin? || community_manager? || general_manager?)
  end

  def rsvp?
    enabled? && future?
  end

  def future?
    record.starts_at >= Time.current
  end

  def enabled?
    # Nil-safe; see DoorPolicy#enabled? for the rationale.
    location&.events_enabled? || false
  end
end