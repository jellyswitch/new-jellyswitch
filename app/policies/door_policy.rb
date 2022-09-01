# typed: true
class DoorPolicy < ApplicationPolicy
  def index?
    enabled? && admin?
  end

  def show?
    enabled? && admin?
  end

  def new?
    enabled? && admin?
  end

  def create?
    enabled? && admin?
  end

  def update?
    enabled? && admin?
  end

  def edit?
    enabled? && admin?
  end

  def open?
    admin? || ((user.allowed_in?(location) && approved?) || billing_disabled?)
  rescue => e
    Honeybadger.notify("DoorPolicy #{__method__} error: #{e}")
    true
  end

  def keys?
    user.present? || (admin? || ((user.allowed_in?(location) && approved?) || billing_disabled?))
  end
  
  def enabled?
    operator.door_integration_enabled?
  end
end
