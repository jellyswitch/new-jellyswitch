# typed: true
class ModulePolicy < ApplicationPolicy
  def index?
    (admin? || superadmin? || community_manager? || general_manager?)
  end

  def announcements?
    (admin? || superadmin? || community_manager? || general_manager?)
  end

  def bulletin_board?
    (admin? || superadmin? || community_manager? || general_manager?)
  end
  
  def events?
    (admin? || superadmin? || community_manager? || general_manager?)
  end

  def door_integration?
    (admin? || superadmin? || community_manager? || general_manager?)
  end

  def rooms?
   (admin? || superadmin? || community_manager? || general_manager?)
  end

  def offices?
    (admin? || superadmin? || community_manager? || general_manager?)
  end

  def credits?
    (admin? || superadmin? || community_manager? || general_manager?)
  end

  def crm?
    (admin? || superadmin? || community_manager? || general_manager?)
  end

  def childcare?
    (admin? || superadmin? || community_manager? || general_manager?)
  end
  
  def reservation_credits_settings?
    (admin? || superadmin? || community_manager? || general_manager?) && credits?
  end

  def childcare_reservations_settings?
    admin? && childcare?
  end
end
