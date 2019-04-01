class UserPolicy < ApplicationPolicy
  def index?
    admin?
  end

  def unapproved?
    admin?
  end

  def show?
    owner_or_admin? 
  end

  def new?
    true # anyone can sign up
  end

  def add_member?
    admin?
  end

  def edit?
    owner_or_admin?
  end

  def create?
    true # anyone can sign up
  end

  def update?
    owner_or_admin?
  end

  def change_password?
    owner_or_admin?
  end

  def update_password?
    owner_or_admin?
  end

  def update_organization?
    admin?
  end

  def memberships?
    owner_or_admin?
  end

  def day_passes?
    owner_or_admin?
  end

  def reservations?
    owner_or_admin?
  end

  def invoices?
    owner_or_admin?
  end

  def approve?
    admin?
  end

  def unapprove?
    admin?
  end

  def edit_billing?
    owner_or_admin?
  end

  def update_billing?
    owner_or_admin?
  end

  private

  def owner_or_admin?
    # Needed because the record itself is the user
    admin? || (is_user? && user == record)
  end
end