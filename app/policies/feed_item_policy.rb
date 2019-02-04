class FeedItemPolicy < ApplicationPolicy
  def index?
    admin?
  end

  def create?
    admin?
  end

  def show?
    admin?
  end
end