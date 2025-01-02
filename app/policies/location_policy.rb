
class LocationPolicy < ApplicationPolicy
  def index?
    (admin? || community_manager? || general_manager?)
  end

  def new?
    admin?
  end

  def show?
    admin? || general_manager?
  end

  def create?
    admin?
  end

  def edit?
    user&.admin_of_location?(record) || user&.general_manager_of_location?(record)
  end

  def update?
    admin? || general_manager?
  end

  def destroy?
    superadmin?
  end

  def allow_hourly? # not used anymore
    admin?
  end

  def new_users_get_free_day_pass? # not used anymore
    admin?
  end

  def visible?
    admin?
  end

  def edit_tracking_pixels?
    admin?
  end
end
