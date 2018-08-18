class UserPolicy < ApplicationPolicy
  def index?
    admin_or_member?
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

  private

  def owner_or_admin?
    # Needed because the record itself is the user
    (user == record) || admin?
  end
end