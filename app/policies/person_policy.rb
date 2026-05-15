class PersonPolicy < ApplicationPolicy
  def index?
    admin? || community_manager? || general_manager? || superadmin?
  end
end
