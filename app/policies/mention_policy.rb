class MentionPolicy < ApplicationPolicy
  def index?
    admin?
  end
end