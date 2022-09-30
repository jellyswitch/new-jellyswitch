
class DoorPunchPolicy < ApplicationPolicy
  def show?
    (admin? || community_manager? || general_manager?)
  end
end