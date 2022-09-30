
class FeedItemPolicy < ApplicationPolicy
  def index?
    (admin? || community_manager? || general_manager?)
  end

  def questions?
    (admin? || community_manager? || general_manager?)
  end

  def activity?
    (admin? || community_manager? || general_manager?)
  end

  def notes?
    (admin? || community_manager? || general_manager?)
  end

  def financial?
    (admin? || community_manager? || general_manager?)
  end

  def create?
    (admin? || community_manager? || general_manager?)
  end

  def show?
    (admin? || community_manager? || general_manager?)
  end

  def destroy?
    (admin? || community_manager? || general_manager?)
  end
end