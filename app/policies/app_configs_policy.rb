class AppConfigsPolicy < ApplicationPolicy
  def index?
    superadmin?
  end
end