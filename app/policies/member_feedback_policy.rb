# typed: true
class MemberFeedbackPolicy < ApplicationPolicy
  def new?
    true
  end

  def create?
    true
  end

  def index?
    admin?
  end

  def show?
    admin?
  end
end