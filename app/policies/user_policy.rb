
class UserPolicy < ApplicationPolicy
  def index?
    has_admin_right?
  end

  def unapproved?
    has_admin_right?
  end

  def archived?
    admin?
  end

  def search?
    has_admin_right?
  end

  def show?
    has_right_over_user?
  end

  def about?
    has_admin_right?
  end

  def childcare?
    has_right_over_user?
  end

  def credits?
    (admin? || community_manager? || general_manager? || community_manager?)
  end

  def add_credits?
    has_admin_right?
  end

  def add_childcare_reservations?
    has_admin_right?
  end

  def ltv?
    has_admin_right?
  end

  def usage?
    has_admin_right?
  end

  def payment_method?
    has_admin_right?
  end

  def membership?
    has_admin_right?
  end

  def admin_day_passes?
    has_admin_right?
  end

  def checkins?
    has_admin_right?
  end

  def organization?
    has_admin_right?
  end

  def admin_invoices?
    has_admin_right?
  end

  def new?
    true # anyone can sign up
  end

  def add_member?
    has_admin_right?
  end

  def edit?
    has_right_over_user?
  end

  def edit_role?
    has_admin_right? && user.role != "community-manager"
  end

  def create?
    true # anyone can sign up
  end

  def update?
    has_right_over_user?
  end

  def change_password?
    has_right_over_user?
  end

  def update_password?
    has_right_over_user?
  end

  def remove_from_organization?
    has_admin_right?
  end

  def update_organization?
    has_admin_right?
  end

  def memberships?
    has_right_over_user?
  end

  def day_passes?
    has_right_over_user?
  end

  def reservations?
    has_right_over_user?
  end

  def past_reservations?
    has_right_over_user?
  end

  def invoices?
    has_right_over_user?
  end

  def approve?
    has_admin_right?
  end

  def unapprove?
    has_admin_right?
  end

  def edit_billing?
    has_right_over_user?
  end

  def update_billing?
    has_right_over_user?
  end

  def set_password_and_send_email?
    has_admin_right?
  end

  def archive?
    has_admin_right?
  end

  def unarchive?
    has_admin_right?
  end

  private

  def has_right_over_user?
    if (is_user? && user == record)
      # the user themself, can access anywhere
      return true
    end

    has_admin_right?
  end

  def has_admin_right?
    if record.is_a?(User)
      (record.original_location_id == nil || record.original_location_id == location.id) && # must be at the same location
      (
        (superadmin? || # superadmin can edit anyone
        (
          (admin? || community_manager? || general_manager?) && # other admin roles
          record.role != "superadmin" # cannot touch superadmin
        ))
      )
    else
      (admin? || community_manager? || general_manager?)
    end
  end


  def owner_or_admin?
    # Needed because the record itself is the user
    admin? || (is_user? && user == record)
  end
end
