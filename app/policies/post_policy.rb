class PostPolicy < ApplicationPolicy
  def index?
    admin? || (user.member_at_operator?(operator) && approved?)
  end

  def new?
    admin? || (user.member_at_operator?(operator) && approved?)
  end

  def create?
    admin? || (user.member_at_operator?(operator) && approved?)
  end

  def show?
    admin? || (user.member_at_operator?(operator) && approved?)
  end
end