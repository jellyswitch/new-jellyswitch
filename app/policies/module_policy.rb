
class ModulePolicy < ApplicationPolicy
  def index?
    (admin? || superadmin? || general_manager?)
  end

  def announcements?
    (admin? || superadmin? || general_manager?)
  end

  def bulletin_board?
    (admin? || superadmin? || general_manager?)
  end

  def events?
    (admin? || superadmin? || general_manager?)
  end

  def door_integration?
    (admin? || superadmin? || general_manager?)
  end

  def rooms?
   (admin? || superadmin? || general_manager?)
  end

  def offices?
    (admin? || superadmin? || general_manager?)
  end

  def credits?
    (admin? || superadmin? || general_manager?)
  end

  def crm?
    (admin? || superadmin? || general_manager?)
  end

  def childcare?
    (admin? || superadmin? || general_manager?)
  end

  def reservation_credits_settings?
    (admin? || superadmin? || general_manager?) && credits?
  end

  def childcare_reservations_settings?
    admin? && childcare?
  end
end
