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
    operator.bulletin_board_enabled?
  end

  def can_see?
    enabled? && (admin? || community_manager? || general_manager? || (user.member_at_operator?(operator) && approved?))
  end
end