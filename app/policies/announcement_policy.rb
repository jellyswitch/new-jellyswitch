class AnnouncementPolicy < ApplicationPolicy
  def index?
    admin? || (member? && approved?)
  end

  def new?
    admin?
  end

  def create?
    admin?
  end
end