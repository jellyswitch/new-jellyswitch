class ProductEmailTemplatePolicy < ApplicationPolicy
  def index?
    admin? || general_manager?
  end

  def edit?
    admin? || general_manager?
  end

  def update?
    admin? || general_manager?
  end

  def toggle_enabled?
    admin? || general_manager?
  end

  def send_log?
    admin? || general_manager?
  end
end
