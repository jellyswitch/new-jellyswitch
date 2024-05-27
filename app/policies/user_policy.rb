
class UserPolicy < ApplicationPolicy
  def index?
    (admin? || community_manager? || general_manager?)
  end

  def unapproved?
    (admin? || community_manager? || general_manager?)
  end

  def archived?
    admin?
  end

  def search?
    (admin? || community_manager? || general_manager?)
  end

  def show?
    (owner_or_admin? || community_manager? || general_manager?)
  end

  def about?
    (admin? || community_manager? || general_manager?)
  end

  def childcare?
    (owner_or_admin? || community_manager? || general_manager?)
  end

  def credits?
    (admin? || community_manager? || general_manager? || community_manager?)
  end

  def add_credits?
    (admin? || community_manager? || general_manager?)
  end

  def add_childcare_reservations?
    (admin? || community_manager? || general_manager?)
  end

  def ltv?
    (admin? || community_manager? || general_manager?)
  end

  def usage?
    (admin? || community_manager? || general_manager?)
  end

  def payment_method?
    (admin? || community_manager? || general_manager?)
  end

  def membership?
    (admin? || community_manager? || general_manager?)
  end

  def admin_day_passes?
    (admin? || community_manager? || general_manager?)
  end

  def checkins?
    (admin? || community_manager? || general_manager?)
  end

  def organization?
    (admin? || community_manager? || general_manager?)
  end

  def admin_invoices?
    (admin? || community_manager? || general_manager?)
  end

  def new?
    true # anyone can sign up
  end

  def add_member?
    (admin? || community_manager? || general_manager?)
  end

  def edit?
    (owner_or_admin? || community_manager? || general_manager?)
  end

  def create?
    true # anyone can sign up
  end

  def update?
    (owner_or_admin? || community_manager? || general_manager?)
  end

  def change_password?
    (owner_or_admin? || community_manager? || general_manager?)
  end

  def update_password?
    (owner_or_admin? || community_manager? || general_manager?)
  end

  def remove_from_organization?
    (admin? || community_manager? || general_manager?)
  end

  def update_organization?
    (admin? || community_manager? || general_manager?)
  end

  def memberships?
    (owner_or_admin? || community_manager? || general_manager?)
  end

  def day_passes?
    (owner_or_admin? || community_manager? || general_manager?)
  end

  def reservations?
    (owner_or_admin? || community_manager? || general_manager?)
  end

  def past_reservations?
    (owner_or_admin? || community_manager? || general_manager?)
  end

  def invoices?
    (owner_or_admin? || community_manager? || general_manager?)
  end

  def approve?
    (admin? || community_manager? || general_manager?)
  end

  def unapprove?
    (admin? || community_manager? || general_manager?)
  end

  def edit_billing?
    (owner_or_admin? || community_manager? || general_manager?)
  end

  def update_billing?
    (owner_or_admin? || community_manager? || general_manager?)
  end

  def set_password_and_send_email?
    (admin? || community_manager? || general_manager?)
  end

  def archive?
    (admin? || community_manager? || general_manager?)
  end

  def unarchive?
    (admin? || community_manager? || general_manager?)
  end

  private

  def owner_or_admin?
    # Needed because the record itself is the user
    admin? || (is_user? && user == record)
  end
end
