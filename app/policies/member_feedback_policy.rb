
class MemberFeedbackPolicy < ApplicationPolicy
  def new?
    is_user?
  end

  def create?
    is_user?
  end

  def index?
    (admin? || community_manager? || general_manager?)
  end

  def show?
    (admin? || community_manager? || general_manager?)
  end
end