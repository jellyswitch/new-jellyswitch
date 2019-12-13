# typed: true
class ModulePolicy < ApplicationPolicy
  def index?
    admin?
  end

  def announcements?
    admin?
  end
  
  def events?
    admin?
  end

  def door_integration?
    admin?
  end

  def rooms?
    admin?
  end
end
