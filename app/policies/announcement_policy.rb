class AnnouncementPolicy < ApplicationPolicy
  def index?
    admin? || (member_at_operator?(operator) && approved?)
  end

  def new?
    admin?
  end

  def create?
    admin?
  end

  private

  def can_see_announcements?
    admin? || (user.allowed_in?(location) && user.approved?)
  end
end