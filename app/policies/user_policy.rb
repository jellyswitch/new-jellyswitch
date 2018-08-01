class UserPolicy < ApplicationPolicy
  def index?
    admin_or_member?
  end

  def show?
    admin_or_member?
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
    user == record
  end
end