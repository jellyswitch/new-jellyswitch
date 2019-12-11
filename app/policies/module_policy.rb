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

end
