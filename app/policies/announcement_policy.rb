class AnnouncementPolicy < ApplicationPolicy
  def index?
    enabled? && user.present? && (billing_disabled? || admin? || (user.member_at_operator?(operator) || community_manager? || general_manager?)) && approved?
  end

  def new?
    enabled? && (admin? || community_manager? || general_manager?)
  end

  def create?
    enabled? && (admin? || community_manager? || general_manager?)
  end

  def enabled?
    operator.announcements_enabled?
  end

  private

  def can_see_announcements?
    admin? || (user.allowed_in?(location) && user.approved?) || community_manager? || general_manager?
  end
end